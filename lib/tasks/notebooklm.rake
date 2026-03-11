# frozen_string_literal: true

namespace :notebooklm do
  desc "Export today's game data for NotebookLM research"
  task export: :environment do
    require "json"

    date = ENV["DATE"] ? Date.parse(ENV["DATE"]) : Date.current
    puts "=" * 60
    puts "📚 NotebookLM Export: #{date}"
    puts "=" * 60

    bridge = NotebookLmBridge.new(date: date)
    result = bridge.export_all

    if result[:games] == 0
      puts "\n⚠️  No games found for #{date}"
      exit
    end

    puts "\n" + "=" * 60
    puts "✅ Export complete: #{result[:games]} games, #{result[:files].count} files"
    puts "📁 Output: #{bridge.export_path}"
    puts ""
    puts "Files:"
    result[:files].each { |f| puts "  - #{File.basename(f)}" }
    puts "=" * 60
  end

  desc "Import NotebookLM research results into reports (as draft)"
  task import: :environment do
    require "json"

    date = ENV["DATE"] ? Date.parse(ENV["DATE"]) : Date.current
    puts "=" * 60
    puts "📥 NotebookLM Import: #{date}"
    puts "=" * 60

    bridge = NotebookLmBridge.new(date: date)
    result = bridge.import_results

    puts "\n" + "=" * 60
    puts "✅ Import complete: #{result[:imported]} reports imported"
    if result[:errors].any?
      puts "⚠️  Errors (#{result[:errors].count}):"
      result[:errors].each { |e| puts "  - #{e}" }
    end
    puts ""
    puts "📝 All imported reports are in DRAFT status."
    puts "   Review at: /admin/reports (filter by draft)"
    puts "=" * 60
  end

  desc "Full pipeline: export -> [manual NotebookLM step] -> import instructions"
  task pipeline: :environment do
    require "json"

    date = ENV["DATE"] ? Date.parse(ENV["DATE"]) : Date.current
    puts "=" * 60
    puts "🔄 NotebookLM Pipeline: #{date}"
    puts "=" * 60

    # Step 1: Export
    puts "\n[Step 1/3] Exporting game data..."
    bridge = NotebookLmBridge.new(date: date)
    result = bridge.export_all

    if result[:games] == 0
      puts "⚠️  No games found for #{date}"
      exit
    end

    puts "✅ Exported #{result[:games]} games"

    # Step 2: Instructions for NotebookLM research
    puts "\n" + "-" * 60
    puts "[Step 2/3] NotebookLM Research (manual or via Claude Code)"
    puts "-" * 60
    puts ""
    puts "Option A: Via Claude Code (recommended)"
    puts "  Run in Claude Code:"
    puts "    \"Research today's NBA games using NotebookLM."
    puts "     Source files are at: #{bridge.export_path}\""
    puts ""
    puts "Option B: Manual"
    puts "  1. Create a NotebookLM notebook"
    puts "  2. Upload the JSON files from: #{bridge.export_path}"
    puts "  3. Also upload research_prompt.md as a text source"
    puts "  4. Query NotebookLM for analysis per game"
    puts "  5. Save results as JSON to: #{bridge.results_path}/"
    puts ""
    puts "  Result file format (one per game):"
    puts '  {'
    puts '    "game_id": 123,'
    puts '    "title": "LAL @ BOS: Deep Research Analysis",'
    puts '    "research_content": "Full markdown analysis...",'
    puts '    "pick": "BOS -3.5",'
    puts '    "confidence": "4/5",'
    puts '    "analysis_summary": "Key finding in one line",'
    puts '    "confidence_factors": ["factor1", "factor2"],'
    puts '    "risk_factors": ["risk1", "risk2"]'
    puts "  }"
    puts ""

    # Step 3: Import instructions
    puts "-" * 60
    puts "[Step 3/3] Import Results"
    puts "-" * 60
    puts ""
    puts "After NotebookLM research is complete, run:"
    puts "  bin/rails notebooklm:import"
    puts ""
    puts "Or with a specific date:"
    puts "  DATE=2026-03-11 bin/rails notebooklm:import"
    puts ""
    puts "=" * 60
  end

  desc "Export a single game for NotebookLM research"
  task :export_game, [:game_id] => :environment do |_, args|
    require "json"

    game = Game.find(args[:game_id])
    date = game.game_date.to_date
    puts "📚 NotebookLM Export: #{game.display_name} (#{date})"

    bridge = NotebookLmBridge.new(date: date)
    context = bridge.send(:load_shared_context)
    file = bridge.export_game(game, context)

    if file
      puts "✅ Exported: #{file}"
      puts "\nJSON content:"
      puts File.read(file)
    else
      puts "❌ Export failed"
    end
  end

  desc "Show export status and available data for today"
  task status: :environment do
    date = ENV["DATE"] ? Date.parse(ENV["DATE"]) : Date.current
    bridge = NotebookLmBridge.new(date: date)

    puts "=" * 60
    puts "📊 NotebookLM Status: #{date}"
    puts "=" * 60

    # Games
    games = Game.where("DATE(game_date) = ?", date).where(sport_id: 1).order(:game_date)
    puts "\n🏀 Games: #{games.count}"
    games.each do |g|
      spread_info = g.home_spread ? "#{g.home_abbr} #{g.home_spread} | O/U #{g.total_line}" : "no lines"
      puts "  #{g.away_abbr} @ #{g.home_abbr} (#{spread_info})"
    end

    # Export status
    export_dir = bridge.export_path
    if Dir.exist?(export_dir)
      files = Dir.glob(export_dir.join("*"))
      puts "\n📁 Export: #{files.count} files in #{export_dir}"
      files.each { |f| puts "  - #{File.basename(f)} (#{(File.size(f) / 1024.0).round(1)}KB)" }
    else
      puts "\n📁 Export: not yet exported"
    end

    # Results status
    results_dir = bridge.results_path
    if Dir.exist?(results_dir)
      files = Dir.glob(results_dir.join("*.json"))
      puts "\n📥 Results: #{files.count} files in #{results_dir}"
      files.each { |f| puts "  - #{File.basename(f)}" }
    else
      puts "\n📥 Results: no results yet"
    end

    # Report status
    reports = Report.joins(:game).where("DATE(games.game_date) = ?", date)
    draft_count = reports.where(status: "draft").count
    published_count = reports.where(status: "published").count
    nlm_count = reports.select { |r| r.parsed_data.dig("notebooklm").present? }.count

    puts "\n📝 Reports: #{reports.count} total (#{published_count} published, #{draft_count} draft, #{nlm_count} with NotebookLM data)"
    puts "=" * 60
  end

  desc "Clean old NotebookLM export/result files (keeps last 7 days)"
  task cleanup: :environment do
    cutoff = 7.days.ago.to_date
    cleaned = 0

    [NotebookLmBridge::EXPORT_DIR, NotebookLmBridge::RESULTS_DIR].each do |dir|
      base = Rails.root.join(dir)
      next unless Dir.exist?(base)

      Dir.glob(base.join("*")).each do |path|
        dirname = File.basename(path)
        begin
          dir_date = Date.parse(dirname)
          if dir_date < cutoff
            FileUtils.rm_rf(path)
            cleaned += 1
            puts "  Removed: #{path}"
          end
        rescue Date::Error
          next
        end
      end
    end

    puts "✅ Cleaned #{cleaned} directories older than #{cutoff}"
  end
end
