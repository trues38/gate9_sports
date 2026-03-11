# frozen_string_literal: true

# G9 Sports - Pre-Analysis Checklist
# 분석 전 데이터 체크 (Neo4j 제거 - 단순화)
# - 부상자 확인
# - 오즈 확인
# - 스케줄 엣지 확인

namespace :pre do
  # 로스터 - 부상자 파일에서 추출 (Neo4j 제거)
  def get_roster(_team_abbr)
    # 로스터는 부상자 목록에서 유추하거나 생략
    # 실제 로스터가 필요하면 ESPN API 직접 호출 가능
    []
  end

  # 부상자 조회
  def get_injuries(team_abbr)
    injuries_path = Rails.root.join('tmp', 'injuries.json')
    return [] unless File.exist?(injuries_path)

    injuries = JSON.parse(File.read(injuries_path))
    injuries[team_abbr] || []
  rescue
    []
  end

  # 팀명 매핑 (abbr → full name)
  def team_full_name(abbr)
    names = {
      'ATL' => 'Atlanta Hawks', 'BOS' => 'Boston Celtics', 'BKN' => 'Brooklyn Nets',
      'CHA' => 'Charlotte Hornets', 'CHI' => 'Chicago Bulls', 'CLE' => 'Cleveland Cavaliers',
      'DAL' => 'Dallas Mavericks', 'DEN' => 'Denver Nuggets', 'DET' => 'Detroit Pistons',
      'GSW' => 'Golden State Warriors', 'HOU' => 'Houston Rockets', 'IND' => 'Indiana Pacers',
      'LAC' => 'LA Clippers', 'LAL' => 'Los Angeles Lakers', 'MEM' => 'Memphis Grizzlies',
      'MIA' => 'Miami Heat', 'MIL' => 'Milwaukee Bucks', 'MIN' => 'Minnesota Timberwolves',
      'NOP' => 'New Orleans Pelicans', 'NYK' => 'New York Knicks', 'OKC' => 'Oklahoma City Thunder',
      'ORL' => 'Orlando Magic', 'PHI' => 'Philadelphia 76ers', 'PHX' => 'Phoenix Suns',
      'POR' => 'Portland Trail Blazers', 'SAC' => 'Sacramento Kings', 'SAS' => 'San Antonio Spurs',
      'TOR' => 'Toronto Raptors', 'UTA' => 'Utah Jazz', 'WAS' => 'Washington Wizards'
    }
    names[abbr] || abbr
  end

  # 팀 약점 패턴 - 제거 (Neo4j 의존 제거)
  def get_team_regime(_team_abbr)
    nil
  end

  # 글로벌 트리거 승률 - 하드코딩 (Neo4j 제거)
  def get_global_triggers
    [
      { name: 'B2B', win_rate: 54, sample_size: 500 },
      { name: '3IN4', win_rate: 52.6, sample_size: 300 },
      { name: 'BAD_MATCHUP_DEFENSE', win_rate: 61.5, sample_size: 150 },
      { name: 'BAD_MATCHUP_OFFENSE', win_rate: 58, sample_size: 120 },
      { name: 'REST_ADVANTAGE', win_rate: 56, sample_size: 200 }
    ]
  end

  # 최근 맞대결 - SQLite에서 조회 (Neo4j 제거)
  def get_head_to_head(away_abbr, home_abbr)
    # GameResult 모델이 있으면 SQLite에서 조회
    # 없으면 빈 배열 반환
    []
  end

  # 팀별 약점 트리거 - 제거 (Neo4j 의존 제거)
  def get_weakness_triggers(_team_abbr)
    []
  end

  desc "경기 분석 전 데이터 체크 (game_id)"
  task :check, [:game_id] => :environment do |_, args|
    require 'json'

    game = Game.find(args[:game_id])
    away = game.away_abbr
    home = game.home_abbr

    puts "=" * 70
    puts "📋 PRE-ANALYSIS CHECKLIST: #{away} @ #{home}"
    puts "📅 #{game.game_date.in_time_zone('Asia/Seoul').strftime('%Y-%m-%d %H:%M')} KST"
    puts "=" * 70
    puts ""

    issues = []
    warnings = []

    # 1. 오즈 체크
    puts "## 1️⃣ 오즈 데이터"
    if game.home_spread.present? && game.total_line.present?
      puts "✅ 스프레드: #{home} #{game.home_spread}"
      puts "✅ 토탈: #{game.total_line}"
    else
      issues << "오즈 데이터 없음"
      puts "❌ 스프레드: #{game.home_spread || 'N/A'}"
      puts "❌ 토탈: #{game.total_line || 'N/A'}"
    end
    puts ""

    # 2. 로스터 체크 (Neo4j)
    puts "## 2️⃣ 로스터 (Neo4j)"

    away_roster = get_roster(away)
    home_roster = get_roster(home)

    if away_roster.any?
      puts "✅ #{away} 로스터: #{away_roster.count}명"
      away_roster.first(5).each do |p|
        puts "   ##{p[:jersey]} #{p[:name]} (#{p[:position]})"
      end
      puts "   ..." if away_roster.count > 5
    else
      issues << "#{away} 로스터 없음"
      puts "❌ #{away} 로스터: 데이터 없음"
    end
    puts ""

    if home_roster.any?
      puts "✅ #{home} 로스터: #{home_roster.count}명"
      home_roster.first(5).each do |p|
        puts "   ##{p[:jersey]} #{p[:name]} (#{p[:position]})"
      end
      puts "   ..." if home_roster.count > 5
    else
      issues << "#{home} 로스터 없음"
      puts "❌ #{home} 로스터: 데이터 없음"
    end
    puts ""

    # 3. 부상자 체크
    puts "## 3️⃣ 부상자"

    away_injuries = get_injuries(away)
    home_injuries = get_injuries(home)

    if away_injuries.any?
      puts "⚠️  #{away} 부상자: #{away_injuries.count}명"
      away_injuries.select { |i| i[:status] == 'Out' || i['status'] == 'Out' }.first(3).each do |i|
        name = i[:name] || i['name']
        injury = i[:injury] || i['injury']
        puts "   🚫 #{name} - OUT (#{injury})"
      end
    else
      puts "✅ #{away} 부상자: 없음 또는 데이터 없음"
      warnings << "#{away} 부상 데이터 확인 필요"
    end
    puts ""

    if home_injuries.any?
      puts "⚠️  #{home} 부상자: #{home_injuries.count}명"
      home_injuries.select { |i| i[:status] == 'Out' || i['status'] == 'Out' }.first(3).each do |i|
        name = i[:name] || i['name']
        injury = i[:injury] || i['injury']
        puts "   🚫 #{name} - OUT (#{injury})"
      end
    else
      puts "✅ #{home} 부상자: 없음 또는 데이터 없음"
      warnings << "#{home} 부상 데이터 확인 필요"
    end
    puts ""

    # 4. 팀 스탯 체크
    puts "## 4️⃣ 팀 스탯"
    stats_path = Rails.root.join('tmp', 'team_stats.json')
    if File.exist?(stats_path)
      stats = JSON.parse(File.read(stats_path))
      away_stats = stats[away]
      home_stats = stats[home]

      if away_stats
        puts "✅ #{away}: #{away_stats['record'] || 'N/A'} (#{away_stats['streak'] || 'N/A'})"
      else
        warnings << "#{away} 스탯 없음"
        puts "⚠️  #{away}: 스탯 데이터 없음"
      end

      if home_stats
        puts "✅ #{home}: #{home_stats['record'] || 'N/A'} (#{home_stats['streak'] || 'N/A'})"
      else
        warnings << "#{home} 스탯 없음"
        puts "⚠️  #{home}: 스탯 데이터 없음"
      end
    else
      warnings << "팀 스탯 파일 없음"
      puts "⚠️  팀 스탯 파일 없음 (data:sync_team_stats 실행 필요)"
    end
    puts ""

    # 5. 스케줄 엣지
    puts "## 5️⃣ 스케줄 엣지"
    if game.away_edge.present?
      puts "⚠️  #{away}: #{game.away_edge}"
    else
      puts "✅ #{away}: 스케줄 엣지 없음"
    end

    if game.home_edge.present?
      puts "⚠️  #{home}: #{game.home_edge}"
    else
      puts "✅ #{home}: 스케줄 엣지 없음"
    end
    puts ""

    # 최종 판정
    puts "=" * 70
    if issues.empty?
      puts "✅ 분석 준비 완료"
      if warnings.any?
        puts ""
        puts "⚠️  경고사항:"
        warnings.each { |w| puts "   - #{w}" }
      end
    else
      puts "❌ 분석 불가 - 다음 이슈 해결 필요:"
      issues.each { |i| puts "   - #{i}" }
      if warnings.any?
        puts ""
        puts "⚠️  추가 경고:"
        warnings.each { |w| puts "   - #{w}" }
      end
    end
    puts "=" * 70
  end

  desc "오늘 모든 경기 체크"
  task check_all: :environment do
    games = Game.where("DATE(game_date) = ?", Date.current).order(:game_date)

    if games.empty?
      puts "오늘 경기 없음"
      exit
    end

    games.each do |game|
      Rake::Task["pre:check"].invoke(game.id)
      Rake::Task["pre:check"].reenable
      puts "\n\n"
    end
  end

  desc "분석용 데이터 JSON 출력 (game_id) - LLM API용"
  task :data, [:game_id] => :environment do |_, args|
    require 'json'

    game = Game.find(args[:game_id])
    away = game.away_abbr
    home = game.home_abbr

    data = {
      # 1. 기본 경기 정보 (SQLite)
      game: {
        id: game.id,
        away: away,
        away_full: team_full_name(away),
        home: home,
        home_full: team_full_name(home),
        date: game.game_date.in_time_zone('Asia/Seoul').strftime('%Y-%m-%d'),
        time: game.game_date.in_time_zone('Asia/Seoul').strftime('%H:%M'),
        spread: game.home_spread,
        total: game.total_line,
        away_edge: game.away_edge,
        home_edge: game.home_edge
      },

      # 2. 로스터 (Neo4j Player)
      rosters: {
        away: get_roster(away),
        home: get_roster(home)
      },

      # 3. 부상자 (ESPN Cache)
      injuries: {
        away: get_injuries(away).select { |i| i['status'] == 'Out' || i[:status] == 'Out' },
        home: get_injuries(home).select { |i| i['status'] == 'Out' || i[:status] == 'Out' }
      },

      # 4. 팀 스탯 (ESPN Cache)
      stats: {},

      # 5. 팀 약점 패턴 (Neo4j TeamRegime)
      team_regimes: {
        away: get_team_regime(away),
        home: get_team_regime(home)
      },

      # 6. 글로벌 트리거 승률 (Neo4j GlobalTrigger)
      global_triggers: get_global_triggers,

      # 7. 최근 맞대결 (Neo4j GameResult)
      head_to_head: get_head_to_head(away, home),

      # 8. 팀별 약점 트리거 (Neo4j WeaknessTrigger)
      weakness_triggers: {
        away: get_weakness_triggers(away),
        home: get_weakness_triggers(home)
      }
    }

    # 팀 스탯
    stats_path = Rails.root.join('tmp', 'team_stats.json')
    if File.exist?(stats_path)
      stats = JSON.parse(File.read(stats_path))
      data[:stats][:away] = stats[away]
      data[:stats][:home] = stats[home]
    end

    puts JSON.pretty_generate(data)
  end

  desc "오늘 모든 경기 분석 데이터 JSON (LLM용)"
  task data_all: :environment do
    require 'json'

    games = Game.where("DATE(game_date) = ?", Date.current).order(:game_date)

    if games.empty?
      puts "오늘 경기 없음"
      exit
    end

    all_data = {
      date: Date.current.strftime('%Y-%m-%d'),
      generated_at: Time.current.in_time_zone('Asia/Seoul').strftime('%Y-%m-%d %H:%M KST'),
      global_triggers: get_global_triggers,
      games: []
    }

    games.each do |game|
      away = game.away_abbr
      home = game.home_abbr

      game_data = {
        id: game.id,
        matchup: "#{away} @ #{home}",
        time: game.game_date.in_time_zone('Asia/Seoul').strftime('%H:%M'),
        spread: game.home_spread ? "#{home} #{game.home_spread}" : nil,
        total: game.total_line,
        edges: {
          away: game.away_edge,
          home: game.home_edge
        },
        rosters: {
          away: get_roster(away).first(8),
          home: get_roster(home).first(8)
        },
        injuries_out: {
          away: get_injuries(away).select { |i| i['status'] == 'Out' || i[:status] == 'Out' }.map { |i| i['name'] || i[:name] },
          home: get_injuries(home).select { |i| i['status'] == 'Out' || i[:status] == 'Out' }.map { |i| i['name'] || i[:name] }
        },
        team_regimes: {
          away: get_team_regime(away),
          home: get_team_regime(home)
        },
        weakness_triggers: {
          away: get_weakness_triggers(away).first(3),
          home: get_weakness_triggers(home).first(3)
        }
      }

      all_data[:games] << game_data
    end

    puts JSON.pretty_generate(all_data)
  end
end
