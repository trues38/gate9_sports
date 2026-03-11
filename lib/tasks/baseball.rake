namespace :baseball do
  desc "Import MLB 2026 season schedule from ESPN"
  task import_schedule: :environment do
    require 'net/http'
    require 'json'

    puts "Fetching MLB 2026 schedule from ESPN..."

    sport = Sport.find_or_create_by!(slug: "baseball") do |s|
      s.name = "Baseball"
      s.active = true
    end

    imported = 0
    skipped = 0

    # Fetch next 14 days of matches
    (0..13).each do |day_offset|
      date = (Date.current + day_offset).strftime("%Y%m%d")
      uri = URI("https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/scoreboard?dates=#{date}")

      begin
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = "Mozilla/5.0"
        response = http.request(request)
        data = JSON.parse(response.body)
      rescue => e
        puts "Error fetching #{date}: #{e.message}"
        next
      end

      events = data["events"] || []
      events.each do |event|
        competition = event["competitions"]&.first
        next unless competition

        home_comp = competition["competitors"]&.find { |c| c["homeAway"] == "home" }
        away_comp = competition["competitors"]&.find { |c| c["homeAway"] == "away" }
        next unless home_comp && away_comp

        event_id = event["id"]
        home_team = home_comp.dig("team", "displayName")
        away_team = away_comp.dig("team", "displayName")
        home_abbr = home_comp.dig("team", "abbreviation")
        away_abbr = away_comp.dig("team", "abbreviation")
        game_time = event["date"]
        venue = competition.dig("venue", "fullName") || "TBD"

        next unless home_team && away_team && game_time

        begin
          parsed_time = Time.parse(game_time)
        rescue
          next
        end

        existing = Game.find_by(external_id: "mlb_#{event_id}")
        if existing
          skipped += 1
          next
        end

        Game.create!(
          sport: sport,
          external_id: "mlb_#{event_id}",
          home_team: home_team,
          away_team: away_team,
          home_abbr: home_abbr,
          away_abbr: away_abbr,
          game_date: parsed_time,
          venue: venue,
          status: "Scheduled",
          league: "mlb",
          league_name: "MLB"
        )
        imported += 1
        print "."
      end
    end

    puts "\n\nImported #{imported} MLB games, skipped #{skipped} existing"
    puts "Total baseball games: #{Game.where(sport: sport).count}"
  end
end
