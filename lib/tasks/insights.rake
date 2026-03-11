namespace :insights do
  desc "Generate SEO insights from today's published reports"
  task generate: :environment do
    reports = Report.where(status: "published")
                    .where(created_at: Date.current.all_day)
                    .where.not(id: Insight.select(:report_id).where.not(report_id: nil))

    if reports.none?
      puts "No new published reports to generate insights for today."
      next
    end

    puts "Found #{reports.count} report(s) to process..."

    reports.find_each do |report|
      print "  Generating insight for Report ##{report.id} (#{report.game&.away_team} vs #{report.game&.home_team})... "
      insight = InsightGenerator.generate_from_report!(report)
      if insight
        puts "OK [Insight ##{insight.id}]"
      else
        puts "SKIPPED (already exists or LLM error)"
      end
    rescue => e
      puts "ERROR: #{e.message}"
    end

    puts "Done."
  end

  desc "Generate SEO insights from all published reports (backfill)"
  task generate_all: :environment do
    reports = Report.where(status: "published")
                    .where.not(id: Insight.select(:report_id).where.not(report_id: nil))

    if reports.none?
      puts "All published reports already have insights."
      next
    end

    puts "Backfilling insights for #{reports.count} report(s)..."

    reports.find_each do |report|
      print "  Report ##{report.id} (#{report.game&.away_team} vs #{report.game&.home_team})... "
      insight = InsightGenerator.generate_from_report!(report)
      if insight
        puts "OK [Insight ##{insight.id}]"
      else
        puts "SKIPPED"
      end
      sleep 1  # LLM rate limit 방지
    rescue => e
      puts "ERROR: #{e.message}"
    end

    puts "Done."
  end
end
