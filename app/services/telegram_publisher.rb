require "net/http"
require "json"

class TelegramPublisher
  TELEGRAM_BOT_TOKEN = ENV.fetch("TELEGRAM_BOT_TOKEN", nil)
  TELEGRAM_CHANNEL_ID = ENV.fetch("TELEGRAM_CHANNEL_ID", nil) # e.g., "@gate9sports"
  API_BASE = "https://api.telegram.org/bot"

  SITE_URL = ENV.fetch("SITE_URL", "http://193.46.243.3")
  MAX_MESSAGE_LENGTH = 4096

  def self.publish_report!(report)
    return unless configured?
    new.publish_report!(report)
  end

  def self.publish_daily_summary!(reports)
    return unless configured?
    new.publish_daily_summary!(reports)
  end

  def self.configured?
    TELEGRAM_BOT_TOKEN.present? && TELEGRAM_CHANNEL_ID.present?
  end

  def publish_report!(report)
    message = format_report(report)
    send_message(message, parse_mode: "HTML")
  end

  def publish_daily_summary!(reports)
    message = format_daily_summary(reports)
    send_message(message, parse_mode: "HTML")
  end

  private

  def format_report(report)
    game = report.game
    edge = report.edge_score
    signals = report.signals
    sport_emoji = sport_emoji_for(game)

    edge_label = edge_label_for(edge)
    signal_str = signals.first.presence || "ANALYSIS"

    # Teaser: show edge/signal but not the actual pick direction for premium
    pick_line = if report.free?
      pick_text = report.pick.presence || report.consensus_pick.presence
      pick_text ? "\n🎯 픽: <b>#{pick_text}</b>" : ""
    else
      "\n🔒 픽: <a href=\"#{report_url(report)}\">전체 분석 보기</a>"
    end

    lines = []
    lines << "#{sport_emoji} <b>G9 Sports | #{game.away_abbr} @ #{game.home_abbr}</b>"
    lines << ""
    lines << "📅 #{format_date(report.published_at || Time.current)}"
    lines << "📊 Edge Score: <b>#{edge || 'N/A'}</b> #{edge_label}"
    lines << "⚡ Signal: <code>#{signal_str}</code>"
    lines << pick_line if pick_line.present?
    lines << ""
    lines << "🔗 <a href=\"#{report_url(report)}\">전체 리포트 보기</a>"
    lines << "📱 <a href=\"#{SITE_URL}/basketball/reports\">모든 분석 보기</a>"
    lines << ""
    lines << "#NBA #스포츠분석 #G9Sports"

    truncate(lines.join("\n"))
  end

  def format_daily_summary(reports)
    return unless reports.any?

    date_str = format_date(Date.current)
    sorted = reports.sort_by { |r| -(r.edge_score || 0) }
    top = sorted.first

    lines = []
    lines << "🏆 <b>G9 Sports | 오늘의 픽</b>"
    lines << ""
    lines << "📅 #{date_str}"
    lines << "📋 분석 게임: #{reports.count}경기"
    lines << ""

    if top
      top_game = top.game
      top_edge = top.edge_score
      top_signal = top.signals.first.presence || "ANALYSIS"
      lines << "🔥 <b>TOP PICK</b>"
      lines << "#{top_game.away_abbr} @ #{top_game.home_abbr}"
      lines << "Edge Score: <b>#{top_edge || 'N/A'}</b> | Signal: <code>#{top_signal}</code>"
      lines << "→ <a href=\"#{report_url(top)}\">자세한 분석 보기</a>"
      lines << ""
    end

    if reports.count > 1
      lines << "📊 <b>오늘의 전체 분석</b>"
      sorted.each do |r|
        game = r.game
        edge = r.edge_score || "N/A"
        fire = (r.edge_score.to_i >= 80) ? " 🔥" : ""
        lines << "• #{game.away_abbr} @ #{game.home_abbr} (Edge #{edge})#{fire}"
      end
      lines << ""
    end

    lines << "🔗 <a href=\"#{SITE_URL}/basketball/reports\">전체 리포트: gate9sports</a>"
    lines << "📱 <a href=\"#{SITE_URL}\">구독하기: gate9sports</a>"
    lines << ""
    lines << "#NBA #스포츠분석 #G9Sports"

    truncate(lines.join("\n"))
  end

  def send_message(text, parse_mode: "HTML")
    uri = URI("#{API_BASE}#{TELEGRAM_BOT_TOKEN}/sendMessage")

    payload = {
      chat_id: TELEGRAM_CHANNEL_ID,
      text: text,
      parse_mode: parse_mode,
      disable_web_page_preview: false
    }

    request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
    request.body = payload.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
      http.request(request)
    end

    result = JSON.parse(response.body)

    if result["ok"]
      msg = result.dig("result", "message_id")
      Rails.logger.info("[Telegram] Message sent: message_id=#{msg}, channel=#{TELEGRAM_CHANNEL_ID}")
      result
    else
      error = result["description"] || "Unknown Telegram API error"
      Rails.logger.error("[Telegram] API error: #{error}")
      nil
    end
  rescue JSON::ParserError => e
    Rails.logger.error("[Telegram] JSON parse error: #{e.message}")
    nil
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error("[Telegram] Timeout: #{e.message}")
    nil
  rescue StandardError => e
    Rails.logger.error("[Telegram] Unexpected error: #{e.class} #{e.message}")
    nil
  end

  def report_url(report)
    sport = report.game.sport&.slug || "basketball"
    "#{SITE_URL}/#{sport}/reports/#{report.id}"
  end

  def format_date(date_or_time)
    t = date_or_time.respond_to?(:to_date) ? date_or_time : date_or_time.to_date
    d = t.respond_to?(:in_time_zone) ? t.in_time_zone("Asia/Seoul") : t
    d.strftime("%Y년 %-m월 %-d일")
  rescue
    date_or_time.to_s
  end

  def edge_label_for(edge)
    return "" if edge.nil?
    case edge.to_i
    when 85..100 then "🔥🔥"
    when 70..84  then "🔥"
    when 55..69  then "⚡"
    else              ""
    end
  end

  def sport_emoji_for(game)
    sport_slug = game.sport&.slug
    case sport_slug
    when "basketball" then "🏀"
    when "baseball"   then "⚾"
    when "soccer"     then "⚽"
    else "🏆"
    end
  end

  def truncate(text)
    return text if text.length <= MAX_MESSAGE_LENGTH
    text[0, MAX_MESSAGE_LENGTH - 4] + "\n..."
  end
end
