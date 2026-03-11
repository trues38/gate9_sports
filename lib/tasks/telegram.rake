# frozen_string_literal: true

namespace :telegram do
  desc "Broadcast today's published report summaries to Telegram channel"
  task daily_broadcast: :environment do
    today = Date.current
    reports = Report.published
                    .joins(:game)
                    .where(games: { game_date: today })

    if reports.any?
      TelegramPublisher.publish_daily_summary!(reports)
      puts "Broadcasted #{reports.count} reports to Telegram (#{today})"
    else
      puts "No published reports for today (#{today})"
    end
  end

  desc "Broadcast a single report to Telegram channel (usage: rake telegram:broadcast_report[ID])"
  task :broadcast_report, [:report_id] => :environment do |_, args|
    unless args[:report_id].present?
      puts "Usage: rake telegram:broadcast_report[REPORT_ID]"
      exit 1
    end

    report = Report.find(args[:report_id])

    unless report.published?
      puts "Report ##{report.id} is not published (status: #{report.status})"
      exit 1
    end

    TelegramPublisher.publish_report!(report)
    puts "Broadcasted Report ##{report.id} to Telegram"
  rescue ActiveRecord::RecordNotFound
    puts "Report ##{args[:report_id]} not found"
    exit 1
  end

  desc "Check Telegram configuration (token + channel set)"
  task check_config: :environment do
    if TelegramPublisher.configured?
      puts "Telegram configured: channel=#{ENV['TELEGRAM_CHANNEL_ID']}"
    else
      puts "Telegram NOT configured. Set TELEGRAM_BOT_TOKEN and TELEGRAM_CHANNEL_ID."
    end
  end
end
