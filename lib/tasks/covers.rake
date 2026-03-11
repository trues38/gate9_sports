namespace :covers do
  desc "Import odds from Covers CSV into Games table"
  task import_odds: :environment do
    require 'csv'

    csv_path = Rails.root.join("..", "data", "nba_covers_odds_regular.csv")

    unless File.exist?(csv_path)
      puts "CSV not found: #{csv_path}"
      puts "Trying full CSV..."
      csv_path = Rails.root.join("..", "data", "nba_covers_odds_full.csv")
    end

    unless File.exist?(csv_path)
      puts "No Covers CSV found!"
      exit 1
    end

    puts "Importing from: #{csv_path}"

    # Team abbreviation mapping (Covers → ESPN)
    abbr_map = {
      "NY" => "NYK", "BKN" => "BKN", "BK" => "BKN",
      "GS" => "GSW", "SA" => "SAS", "NO" => "NOP",
      "PHO" => "PHX", "UTAH" => "UTA", "WSH" => "WAS"
    }

    updated = 0
    not_found = 0

    CSV.foreach(csv_path, headers: true) do |row|
      date = Date.parse(row["date"]) rescue nil
      next unless date

      away_abbr = abbr_map[row["away_abbr"]] || row["away_abbr"]
      home_abbr = abbr_map[row["home_abbr"]] || row["home_abbr"]

      # Find game by date and teams
      game = Game.joins(:sport)
                 .where(sports: { slug: "basketball" })
                 .where("DATE(game_date) = ?", date)
                 .where(away_abbr: away_abbr, home_abbr: home_abbr)
                 .first

      unless game
        # Try reverse (away/home might be swapped)
        game = Game.joins(:sport)
                   .where(sports: { slug: "basketball" })
                   .where("DATE(game_date) = ?", date)
                   .where(away_abbr: home_abbr, home_abbr: away_abbr)
                   .first
      end

      unless game
        not_found += 1
        next
      end

      # Parse spread line
      spread_team = row["spread_team"]
      spread_line = row["spread_line"].to_f rescue nil
      total_line = row["total_line"].to_f rescue nil

      if spread_line && spread_team
        # spread_team won ATS, so they had the spread
        if spread_team == home_abbr || abbr_map.values.include?(spread_team) && abbr_map.key(spread_team) == home_abbr
          game.home_spread = spread_line
          game.away_spread = -spread_line
        else
          game.away_spread = spread_line
          game.home_spread = -spread_line
        end
      end

      game.total_line = total_line if total_line && total_line > 0

      # Update scores if available
      if row["home_score"].present? && row["away_score"].present?
        game.home_score = row["home_score"].to_i
        game.away_score = row["away_score"].to_i
        game.status = "finished"
      end

      if game.changed?
        game.save!
        updated += 1
        print "." if updated % 50 == 0
      end
    end

    puts "\nDone! Updated: #{updated}, Not found: #{not_found}"
  end

  desc "Scrape today's odds from Covers via Jina Reader"
  task fetch_today: :environment do
    require 'net/http'
    require 'json'

    today = Date.current.strftime('%Y-%m-%d')
    puts "Fetching Covers odds for #{today}..."

    # Jina Reader로 Covers.com 스크래핑
    jina_url = "https://r.jina.ai/https://www.covers.com/sports/nba/matchups?selectedDate=#{today}"

    uri = URI(jina_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 60

    request = Net::HTTP::Get.new(uri)
    request['Accept'] = 'text/plain'
    request['User-Agent'] = 'Mozilla/5.0'

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      puts "Error: #{response.code} #{response.message}"
      exit 1
    end

    markdown = response.body
    puts "Fetched #{markdown.length} bytes"

    # 간단한 파싱 (스프레드/토탈 찾기)
    # 상세 파싱은 Python 스크립트 사용 권장
    games = parse_covers_markdown(markdown, today)

    puts "Found #{games.length} games"

    # Games 테이블 업데이트
    sport = Sport.find_by(slug: "basketball")
    updated = 0

    games.each do |g|
      game = Game.where(sport: sport)
                 .where("DATE(game_date) = ?", today)
                 .where(away_abbr: g[:away], home_abbr: g[:home])
                 .first

      next unless game

      game.away_spread = g[:away_spread] if g[:away_spread]
      game.home_spread = g[:home_spread] if g[:home_spread]
      game.total_line = g[:total] if g[:total]

      if game.changed?
        game.save!
        updated += 1
        puts "  Updated: #{g[:away]} @ #{g[:home]} | Spread: #{g[:home_spread]} | Total: #{g[:total]}"
      end
    end

    puts "Done! Updated #{updated} games"
  end

  desc "Full scrape using Python script"
  task scrape_range: :environment do
    script_path = Rails.root.join("..", "scripts", "jina_covers_scraper.py")
    output_path = Rails.root.join("..", "data", "nba_covers_odds_latest.csv")

    start_date = ENV['START'] || (Date.current - 7.days).strftime('%Y-%m-%d')
    end_date = ENV['END'] || Date.current.strftime('%Y-%m-%d')

    cmd = "python3 #{script_path} --start #{start_date} --end #{end_date} --output #{output_path}"
    puts "Running: #{cmd}"

    system(cmd)

    puts "Now run: rake covers:import_odds to import into database"
  end
end

def parse_covers_markdown(markdown, date)
  games = []

  # 팀 약어 정규화
  abbr_map = {
    'NY' => 'NYK', 'BK' => 'BKN', 'GS' => 'GSW',
    'SA' => 'SAS', 'NO' => 'NOP', 'PHO' => 'PHX', 'UTAH' => 'UTA'
  }

  # 스코어 테이블 파싱: | HOU | 28 | 24 | 34 | 25 | 111 |
  score_matches = markdown.scan(/\|\s*([A-Z]{2,4})\s*\|(?:\s*\d+\s*\|)+\s*(\d+)\s*\|/)

  score_matches.each_slice(2) do |away_match, home_match|
    next unless away_match && home_match
    next if away_match[0] == 'Team' # 헤더 스킵

    away_abbr = abbr_map[away_match[0]] || away_match[0]
    home_abbr = abbr_map[home_match[0]] || home_match[0]

    games << {
      away: away_abbr,
      home: home_abbr,
      away_spread: nil,
      home_spread: nil,
      total: nil
    }
  end

  # 스프레드 파싱: "HOU +4" or "LAL -3.5"
  spread_matches = markdown.scan(/([A-Z]{2,4})\s*([+-]\d+\.?\d*)/)

  games.each do |game|
    spread_matches.each do |team, spread|
      team = abbr_map[team] || team
      spread_val = spread.to_f

      if team == game[:home]
        game[:home_spread] = spread_val
        game[:away_spread] = -spread_val
        break
      elsif team == game[:away]
        game[:away_spread] = spread_val
        game[:home_spread] = -spread_val
        break
      end
    end
  end

  # 토탈 파싱: "Over 217" or "Under 215" or "O/U 220"
  total_matches = markdown.scan(/(?:Over|Under|O\/U)\s*(\d+\.?\d*)/i)
  games.each_with_index do |game, idx|
    game[:total] = total_matches[idx]&.first&.to_f if total_matches[idx]
  end

  games
end
