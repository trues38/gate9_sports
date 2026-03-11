class HomeController < ApplicationController
  def index
    return unless current_sport

    # Date navigation
    @selected_date = parse_date_safely(params[:date]) || Date.current
    @yesterday = @selected_date - 1.day
    @tomorrow = @selected_date + 1.day

    start_of_day = @selected_date.in_time_zone("Asia/Seoul").beginning_of_day
    end_of_day = @selected_date.in_time_zone("Asia/Seoul").end_of_day

    base_games = current_sport.games.where(game_date: start_of_day..end_of_day)
    base_games = base_games.where(league: current_league) if current_league.present?

    @games = base_games.order(:game_date)

    # If no games for selected date, optionally show upcoming (optional, keeping current logic for now)
    if @games.empty? && @selected_date == Date.current
      @games = current_sport.games.upcoming.limit(10)
      @showing_upcoming = true
    end

    @recent_reports = current_sport.reports.published.limit(5)
    @recent_insights = current_sport.insights.published.limit(5)
    @report_performance = Report.stats(current_sport.reports.published)
    @recent_results = current_sport.reports.published.with_result.order(result_recorded_at: :desc, published_at: :desc).limit(5)

    # Upcoming games with schedule edge for the Edge Alert section
    @edge_games = current_sport.games
                               .where("game_date >= ?", Date.current)
                               .where.not(schedule_note: [nil, ""])
                               .order(:game_date)
                               .limit(3)
  end

  def subscribe
    email = params[:email]

    if email.present? && email.match?(URI::MailTo::EMAIL_REGEXP)
      # Store email in a waitlist file for now (MVP approach)
      waitlist_file = Rails.root.join("tmp", "waitlist.txt")
      File.open(waitlist_file, "a") do |f|
        f.puts "#{Time.current.iso8601},#{email}"
      end

      redirect_to root_path, notice: "신청 완료! 출시 소식을 가장 먼저 전달드리겠습니다."
    else
      redirect_to root_path, alert: "유효한 이메일 주소를 입력해주세요."
    end
  end

  private

  def parse_date_safely(date_string)
    return nil if date_string.blank?
    Date.parse(date_string)
  rescue ArgumentError, TypeError
    nil
  end
end
