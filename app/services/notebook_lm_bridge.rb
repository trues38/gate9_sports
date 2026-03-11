# frozen_string_literal: true

# NotebookLmBridge - Data exchange between Rails DB and NotebookLM MCP
#
# NotebookLM MCP tools run in Claude Code, not in Rails runtime.
# This service handles the data transformation:
#   1. Export: Rails DB -> structured JSON files (tmp/notebooklm/)
#   2. Import: NotebookLM research results -> Report records
#
# Usage:
#   bridge = NotebookLmBridge.new(date: Date.current)
#   bridge.export_all          # writes to tmp/notebooklm/export/
#   bridge.import_results      # reads from tmp/notebooklm/results/
#
class NotebookLmBridge
  EXPORT_DIR = "tmp/notebooklm/export"
  RESULTS_DIR = "tmp/notebooklm/results"
  MANIFEST_FILE = "manifest.json"

  attr_reader :date, :export_path, :results_path

  def initialize(date: Date.current)
    @date = date
    @export_path = Rails.root.join(EXPORT_DIR, date.strftime("%Y-%m-%d"))
    @results_path = Rails.root.join(RESULTS_DIR, date.strftime("%Y-%m-%d"))
  end

  # ============================================================
  # EXPORT: Gather all game data and write JSON files
  # ============================================================

  def export_all
    games = fetch_todays_games
    if games.empty?
      log "No games found for #{date}"
      return { games: 0, files: [] }
    end

    FileUtils.mkdir_p(export_path)

    # Load shared data once
    context = load_shared_context

    files = []
    games.each do |game|
      file = export_game(game, context)
      files << file if file
    end

    # Write manifest
    manifest = build_manifest(games, files)
    manifest_path = export_path.join(MANIFEST_FILE)
    File.write(manifest_path, JSON.pretty_generate(manifest))
    files << manifest_path.to_s

    # Write combined research prompt
    prompt_path = export_path.join("research_prompt.md")
    File.write(prompt_path, build_research_prompt(games, context))
    files << prompt_path.to_s

    log "Exported #{files.count} files for #{games.count} games"
    { games: games.count, files: files }
  end

  def export_game(game, context = nil)
    context ||= load_shared_context

    data = build_game_export(game, context)
    filename = "game_#{game.id}_#{game.away_abbr}_at_#{game.home_abbr}.json"
    filepath = export_path.join(filename)

    FileUtils.mkdir_p(export_path)
    File.write(filepath, JSON.pretty_generate(data))
    log "  Exported: #{filename}"
    filepath.to_s
  rescue => e
    log "  ERROR exporting game ##{game.id}: #{e.message}"
    nil
  end

  # ============================================================
  # IMPORT: Read NotebookLM research results into Report records
  # ============================================================

  def import_results
    unless Dir.exist?(results_path)
      log "No results directory: #{results_path}"
      return { imported: 0, errors: [] }
    end

    result_files = Dir.glob(results_path.join("*.json")).sort
    if result_files.empty?
      log "No result files found in #{results_path}"
      return { imported: 0, errors: [] }
    end

    imported = 0
    errors = []

    result_files.each do |file|
      begin
        data = JSON.parse(File.read(file), symbolize_names: true)
        next if data[:game_id].blank?

        game = Game.find_by(id: data[:game_id])
        unless game
          errors << "Game ##{data[:game_id]} not found"
          next
        end

        report = Report.find_or_initialize_by(game: game)
        apply_research_to_report(report, data, game)
        imported += 1
        log "  Imported: #{game.away_abbr} @ #{game.home_abbr} -> Report ##{report.id}"
      rescue => e
        errors << "#{File.basename(file)}: #{e.message}"
        log "  ERROR importing #{File.basename(file)}: #{e.message}"
      end
    end

    log "Import complete: #{imported} reports, #{errors.count} errors"
    { imported: imported, errors: errors }
  end

  # Import a single research result from a hash (for programmatic use)
  def import_single(game_id:, research_content:, research_analysis: nil, confidence: nil, pick: nil)
    game = Game.find(game_id)
    report = Report.find_or_initialize_by(game: game)

    report.assign_attributes(
      title: "#{game.away_abbr} @ #{game.home_abbr}: NotebookLM Deep Analysis",
      content: research_content,
      pick: pick,
      confidence: confidence,
      status: "draft",
      structured_data: {
        source: "notebooklm",
        research_analysis: research_analysis,
        generated_at: Time.current.iso8601,
        date: date.to_s
      }.to_json
    )

    report.save!
    log "Imported single: Report ##{report.id} for #{game.display_name}"
    report
  end

  private

  # ============================================================
  # DATA BUILDING
  # ============================================================

  def build_game_export(game, ctx)
    engine_picks = extract_engine_picks(game, ctx[:engine_data])
    injuries = load_injuries_for_game(game, ctx[:injuries])
    triggers = load_triggers_for_game(game, ctx)

    {
      game_id: game.id,
      date: date.to_s,
      time_kst: game.game_date&.in_time_zone("Asia/Seoul")&.strftime("%H:%M"),
      time_et: game.game_date&.in_time_zone("America/New_York")&.strftime("%H:%M"),
      away_team: game.away_abbr,
      home_team: game.home_abbr,
      away_full: game.away_team,
      home_full: game.home_team,
      venue: game.venue,
      status: game.status,

      odds: {
        home_spread: game.home_spread&.to_f,
        away_spread: game.away_spread&.to_f,
        total: game.total_line&.to_f,
        opening_spread: game.opening_spread&.to_f,
        opening_total: game.opening_total&.to_f,
        spread_movement: game.spread_movement&.to_f,
        total_movement: game.total_movement&.to_f,
        public_home_pct: game.public_home_pct,
        public_over_pct: game.public_over_pct
      },

      records: {
        away: {
          record: game.away_record,
          road_record: game.away_road_record,
          edge: game.away_edge
        },
        home: {
          record: game.home_record,
          home_record: game.home_home_record,
          edge: game.home_edge
        }
      },

      injuries: injuries,

      team_stats: {
        away: build_team_stats(game.away_abbr, ctx),
        home: build_team_stats(game.home_abbr, ctx)
      },

      engine_picks: engine_picks,
      triggers: triggers,
      h2h_summary: game.h2h_summary,
      schedule_note: game.schedule_note,

      context: build_game_research_context(game, engine_picks, injuries, triggers, ctx)
    }
  end

  def build_team_stats(abbr, ctx)
    advanced = ctx[:advanced_stats][abbr] || {}
    trends = ctx[:team_trends][abbr] || {}

    {
      off_rtg: advanced["off_rtg"],
      off_rank: advanced["off_rank"],
      def_rtg: advanced["def_rtg"],
      def_rank: advanced["def_rank"],
      net_rtg: advanced["net_rtg"],
      net_rank: advanced["net_rank"],
      pace: advanced["pace"],
      record: trends["record"],
      current_streak: trends["current_streak"],
      last_5: trends["last_5"],
      last_10: trends["last_10"],
      ats_record: trends.dig("ats", "record"),
      ats_home: trends.dig("ats", "home"),
      ats_away: trends.dig("ats", "away"),
      ou_record: trends.dig("ou", "record")
    }.compact
  end

  def build_game_research_context(game, engine_picks, injuries, triggers, ctx)
    lines = []
    lines << "=== RESEARCH CONTEXT FOR: #{game.away_abbr} @ #{game.home_abbr} ==="
    lines << "Date: #{date} | Venue: #{game.venue || 'TBD'}"
    lines << ""

    # Odds context
    if game.home_spread
      lines << "## Market Lines"
      lines << "Spread: #{game.home_abbr} #{game.home_spread} (opened #{game.opening_spread || 'N/A'})"
      lines << "Total: #{game.total_line} (opened #{game.opening_total || 'N/A'})"
      if game.spread_movement&.nonzero?
        lines << "Line movement: spread #{game.spread_movement > 0 ? '+' : ''}#{game.spread_movement}, total #{game.total_movement&.nonzero? ? "#{game.total_movement > 0 ? '+' : ''}#{game.total_movement}" : 'steady'}"
      end
      if game.public_home_pct
        lines << "Public: #{game.public_home_pct}% on #{game.home_abbr}, #{game.public_over_pct}% over"
      end
      lines << ""
    end

    # Engine picks context
    if engine_picks.present?
      lines << "## G9 Engine Quantitative Analysis (Backtested)"
      if engine_picks[:ml]
        ml = engine_picks[:ml]
        lines << "- ML Upset Alert: #{ml[:upset_alert]} | #{ml[:signal]}"
        lines << "  Favorite #{ml[:favorite]} flow: #{ml[:fav_flow]}, Underdog #{ml[:underdog]} flow: #{ml[:dog_flow]}"
      end
      if engine_picks[:spread]
        sp = engine_picks[:spread]
        lines << "- Spread: #{sp[:signal]} | #{sp[:recommended]} (#{sp[:spread_tier]}, historical cover #{sp[:historical_cover_pct]}%)"
      end
      if engine_picks[:pickem]
        pk = engine_picks[:pickem]
        lines << "- Pickem: #{pk[:signal]} | #{pk[:recommended]} +#{pk[:spread]} (edge #{pk[:pickem_edge_score]})"
      end
      if engine_picks[:total]
        tot = engine_picks[:total]
        lines << "- Total: #{tot[:signal]} | #{tot[:pick_direction]} (expected #{tot[:expected_total]} vs line #{tot[:total_line]}, diff #{tot[:diff]})"
      end
      lines << ""
    end

    # Injuries context
    away_injuries = injuries[:away] || []
    home_injuries = injuries[:home] || []
    if away_injuries.any? || home_injuries.any?
      lines << "## Injuries"
      if away_injuries.any?
        lines << "#{game.away_abbr}: #{away_injuries.map { |i| "#{i[:player]} (#{i[:status]}: #{i[:detail]})" }.join(', ')}"
      end
      if home_injuries.any?
        lines << "#{game.home_abbr}: #{home_injuries.map { |i| "#{i[:player]} (#{i[:status]}: #{i[:detail]})" }.join(', ')}"
      end
      lines << ""
    end

    # Triggers context
    if triggers.any?
      lines << "## Detected Triggers (Backtested)"
      triggers.each do |t|
        lines << "- #{t[:type]} on #{t[:team]}: #{t[:detail]} (hit rate #{t[:hit_rate]}%, signal #{t[:signal]})"
      end
      lines << ""
    end

    # H2H
    if game.h2h_summary.present?
      lines << "## Head-to-Head"
      lines << game.h2h_summary
      lines << ""
    end

    # Schedule edges
    if game.home_edge.present? || game.away_edge.present?
      lines << "## Schedule Edges"
      lines << "Home (#{game.home_abbr}): #{game.home_edge || 'none'}"
      lines << "Away (#{game.away_abbr}): #{game.away_edge || 'none'}"
      lines << ""
    end

    lines << "## Research Request"
    lines << "Analyze this matchup for betting value. Consider:"
    lines << "1. Is the spread accurate given team strength and situational factors?"
    lines << "2. Are there exploitable mismatches or rest/fatigue edges?"
    lines << "3. What does the injury report imply for scoring pace and total?"
    lines << "4. Where is the market potentially mispricing this game?"
    lines << "5. What is the highest-confidence bet (spread, total, or moneyline)?"

    lines.join("\n")
  end

  def build_research_prompt(games, ctx)
    lines = []
    lines << "# G9 Sports - NotebookLM Research Request"
    lines << "# Date: #{date}"
    lines << "# Games: #{games.count}"
    lines << ""
    lines << "Use the per-game JSON files as source material."
    lines << "For each game, provide deep analysis covering:"
    lines << ""
    lines << "1. **Market Efficiency**: Is the line sharp or soft? Line movement signals?"
    lines << "2. **Situational Edges**: B2B, rest, travel, revenge, schedule spots"
    lines << "3. **Matchup Analysis**: Pace, style, key player impacts"
    lines << "4. **Injury Impact**: How do absences shift expected value?"
    lines << "5. **Engine Correlation**: Do quantitative signals align with qualitative reads?"
    lines << "6. **Final Verdict**: Best bet with confidence rating (1-5 stars)"
    lines << ""
    lines << "---"
    lines << ""

    games.each do |game|
      lines << "## #{game.away_abbr} @ #{game.home_abbr}"
      if game.home_spread
        lines << "Line: #{game.home_abbr} #{game.home_spread} | O/U #{game.total_line}"
      end
      lines << "Time: #{game.game_date&.in_time_zone('Asia/Seoul')&.strftime('%H:%M')} KST"
      lines << ""
    end

    lines.join("\n")
  end

  def build_manifest(games, files)
    {
      date: date.to_s,
      generated_at: Time.current.iso8601,
      game_count: games.count,
      files: files.map { |f| File.basename(f) },
      games: games.map { |g|
        {
          game_id: g.id,
          matchup: g.display_name,
          spread: g.home_spread&.to_f,
          total: g.total_line&.to_f
        }
      }
    }
  end

  # ============================================================
  # IMPORT HELPERS
  # ============================================================

  def apply_research_to_report(report, data, game)
    content = data[:research_content] || data[:content]
    return if content.blank?

    existing_structured = report.parsed_data rescue {}

    report.assign_attributes(
      title: data[:title] || "#{game.away_abbr} @ #{game.home_abbr}: Deep Research Analysis",
      content: content,
      pick: data[:pick] || extract_pick_from_content(content),
      confidence: data[:confidence] || extract_confidence_from_content(content),
      status: "draft", # Always draft - admin reviews before publish
      structured_data: existing_structured.merge(
        "notebooklm" => {
          "source" => "notebooklm_research",
          "imported_at" => Time.current.iso8601,
          "analysis_summary" => data[:analysis_summary],
          "confidence_factors" => data[:confidence_factors],
          "risk_factors" => data[:risk_factors]
        }
      ).to_json
    )

    report.save!
  end

  def extract_pick_from_content(content)
    # Try common patterns
    if (m = content.match(/PICK:\s*\*?\*?(.+?)\*?\*?\s*$/i))
      m[1].strip
    elsif (m = content.match(/Final Pick:\s*\*?\*?(.+?)\*?\*?\s*$/i))
      m[1].strip
    end
  end

  def extract_confidence_from_content(content)
    if (m = content.match(/([★⭐]+[☆]*)/))
      stars = m[1].count("★") + m[1].count("⭐")
      "#{stars}/5"
    end
  end

  # ============================================================
  # DATA LOADING
  # ============================================================

  def fetch_todays_games
    Game.where("DATE(game_date) = ?", date)
        .where(sport_id: 1)
        .order(:game_date)
  end

  def load_shared_context
    {
      advanced_stats: load_advanced_stats,
      team_trends: load_team_trends,
      injuries: load_injuries,
      engine_data: load_engine_data
    }
  end

  def load_advanced_stats
    WeaknessPrediction.load_advanced_stats
  rescue => e
    log "WARNING: Could not load advanced stats: #{e.message}"
    {}
  end

  def load_team_trends
    path = Rails.root.join("tmp", "team_trends.json")
    return {} unless File.exist?(path)
    JSON.parse(File.read(path))
  rescue
    {}
  end

  def load_injuries
    path = Rails.root.join("tmp", "injuries.json")
    return {} unless File.exist?(path)
    JSON.parse(File.read(path))
  rescue
    {}
  end

  def load_injuries_for_game(game, all_injuries)
    away_key = find_injury_key(all_injuries, game.away_team, game.away_abbr)
    home_key = find_injury_key(all_injuries, game.home_team, game.home_abbr)

    {
      away: parse_injury_list(all_injuries[away_key]),
      home: parse_injury_list(all_injuries[home_key])
    }
  end

  def find_injury_key(injuries, full_name, abbr)
    injuries.keys.find { |k| k == full_name || k == abbr || k.include?(abbr.to_s) } || full_name
  end

  def parse_injury_list(raw)
    return [] if raw.blank?

    case raw
    when Array
      raw.map do |entry|
        case entry
        when Hash
          { player: entry["name"] || entry["player"], status: entry["status"], detail: entry["detail"] || entry["injury"] }
        when String
          { player: entry, status: "unknown", detail: nil }
        end
      end.compact
    when Hash
      raw.map { |name, info| { player: name, status: info.to_s, detail: nil } }
    else
      []
    end
  end

  def load_engine_data
    engine = G9EngineService.new
    engine.analyze_all(date.strftime("%Y%m%d"))
  rescue => e
    log "WARNING: G9Engine unavailable (#{e.message})"
    nil
  end

  def extract_engine_picks(game, engine_data)
    return nil if engine_data.nil?

    away = game.away_abbr.to_s.upcase
    home = game.home_abbr.to_s.upcase

    ml     = engine_data[:ml]&.find     { |p| p[:away].to_s.upcase == away && p[:home].to_s.upcase == home }
    spread = engine_data[:spread]&.find { |p| p[:away].to_s.upcase == away && p[:home].to_s.upcase == home }
    pickem = engine_data[:pickem]&.find { |p| p[:away].to_s.upcase == away && p[:home].to_s.upcase == home }
    total  = engine_data[:total]&.find  { |p| p[:away].to_s.upcase == away && p[:home].to_s.upcase == home }

    return nil if ml.nil? && spread.nil? && pickem.nil? && total.nil?

    { ml: ml, spread: spread, pickem: pickem, total: total }
  end

  def load_triggers_for_game(game, ctx)
    WeaknessPrediction.detect_triggers_for_game(game)
    preds = WeaknessPrediction.where(game: game)

    global_triggers = {
      "B2B" => { hit_rate: 54, signal: "NEUTRAL" },
      "3IN4" => { hit_rate: 52.6, signal: "NEUTRAL" },
      "BAD_MATCHUP_DEFENSE" => { hit_rate: 61.5, signal: "MODERATE" },
      "BAD_MATCHUP_OFFENSE" => { hit_rate: 58, signal: "MODERATE" },
      "REVENGE" => { hit_rate: 55, signal: "NEUTRAL" },
      "REST_ADVANTAGE" => { hit_rate: 56, signal: "NEUTRAL" }
    }

    preds.map do |p|
      gt = global_triggers[p.trigger_type] || {}
      {
        type: p.trigger_type,
        team: p.team,
        detail: p.trigger_detail,
        hit_rate: gt[:hit_rate] || 50,
        signal: gt[:signal] || "NEUTRAL"
      }
    end
  rescue
    []
  end

  def log(msg)
    prefix = "[NotebookLM Bridge]"
    puts "#{prefix} #{msg}"
    Rails.logger.info("#{prefix} #{msg}") if defined?(Rails) && Rails.logger
  end
end
