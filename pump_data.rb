# G9 Data Pumping Script
# Populates the DB with rich sample data for testing and display

require_relative 'config/environment'

puts "🚀 Starting G9 Data Pumping..."

# 1. Ensure Sports exist
basketball = Sport.find_or_create_by!(slug: "basketball") { |s| s.name = "Basketball"; s.icon = "basketball"; s.active = true }
baseball = Sport.find_or_create_by!(slug: "baseball") { |s| s.name = "Baseball"; s.icon = "target"; s.active = true }
soccer = Sport.find_or_create_by!(slug: "soccer") { |s| s.name = "Soccer"; s.icon = "football"; s.active = true }

# 2. Clear existing data to avoid mess (Optional, but good for consistent testing)
# Game.destroy_all
# Report.destroy_all
# Insight.destroy_all

# Helper to create meaningful reports
def create_sample_report(game, pick, result = nil)
  Report.find_or_create_by!(game: game, pick: pick) do |r|
    r.title = "#{game.away_abbr} @ #{game.home_abbr} 분석 리포트"
    r.confidence = ["★★★☆☆", "★★★★☆", "★★★★★"].sample
    r.status = "published"
    r.published_at = Time.current - rand(1..12).hours
    r.free = [true, false].sample
    r.result = result
    r.pick_type = "spread"
    r.pick_side = "home"
    r.pick_line = game.home_spread
    r.content = <<~CONTENT
      ## 🎯 분석 결론
      
      본 경기는 데이터상 **#{pick}** 방향이 매우 유력합니다.
      현재 #{game.home_team}의 최근 흐름과 #{game.away_team}의 부상 소식을 종합할 때 엣지가 발생했습니다.
      
      ## 📊 주요 지표
      - 상대 전적: 최근 5경기 #{rand(3..5)}승 #{rand(0..2)}패 (홈팀 기준)
      - 라인 변동: 오프닝 대비 #{['+0.5', '-0.5', '+1.0'].sample} 변동 확인
      
      ## 📝 추천 사유
      #{game.home_team}은 최근 홈에서 평균 #{rand(110..120)}득점을 기록하며 화력이 폭발하고 있습니다. 반면 #{game.away_team}은 핵심 선수의 결장으로 수비 조직력이 무너진 상태입니다.
    CONTENT
  end
end

# 3. Create Finished Games (Yesterday)
yesterday = 1.day.ago.beginning_of_day + 10.hours
[
  ["LAL", "GSW", 112, 118, "GSW -4.5", "win"],
  ["BOS", "PHI", 105, 98, "BOS -6.5", "win"],
  ["MIL", "NYK", 120, 125, "MIL -2.5", "loss"],
  ["MCI", "LIV", 2, 2, "OVER 2.5", "win"]
].each_with_index do |(away, home, a_score, h_score, pick, res), i|
  g = Game.find_or_create_by!(external_id: "hist_#{i}_#{away}_#{home}") do |game|
    game.sport = basketball
    game.league = "nba"
    game.league_name = "NBA"
    game.away_team = away; game.home_team = home
    game.away_abbr = away; game.home_abbr = home
    game.game_date = yesterday + i.hours
    game.status = "finished"
    game.home_score = h_score
    game.away_score = a_score
  end
  create_sample_report(g, pick, res)
end

# 4. Create Today's Games (NBA)
nba_today = [
  ["DAL", "BOS", -4.5, 228.5, true],
  ["MIA", "CHA", -8.5, 215.0, true],
  ["POR", "HOU", +6.5, 220.5, false],
  ["NYK", "DEN", -2.5, 224.0, true],
  ["NOP", "PHX", +3.5, 230.5, true],
  ["LAC", "SAS", -12.5, 218.0, false],
  ["IND", "LAL", +5.5, 235.0, true]
]

nba_today.each_with_index do |(away, home, spread, total, edge), i|
  g = Game.find_or_create_by!(external_id: "today_nba_#{i}") do |game|
    game.sport = basketball
    game.league = "nba"
    game.league_name = "NBA"
    game.away_team = away; game.home_team = home
    game.away_abbr = away; game.home_abbr = home
    game.game_date = Time.current.beginning_of_day + 9.hours + (i * 30).minutes
    game.status = "scheduled"
    game.home_spread = spread
    game.total_line = total
    game.home_edge = edge ? rand(2.5..8.5) : nil
  end
  create_sample_report(g, "#{home} #{spread}") if edge || i < 3
end

# 5. Create Soccer Games (Today)
soccer_today = [
  ["ARS", "MCI", "Premier League"],
  ["RMA", "BAR", "La Liga"],
  ["MUN", "CHE", "Premier League"]
]

soccer_today.each_with_index do |(away, home, league), i|
  g = Game.find_or_create_by!(external_id: "today_soc_#{i}") do |game|
    game.sport = soccer
    game.league = league.parameterize
    game.league_name = league
    game.away_team = away; game.home_team = home
    game.away_abbr = away; game.home_abbr = home
    game.game_date = Time.current.beginning_of_day + 20.hours + i.hours
    game.status = "scheduled"
    game.home_spread = [0, -0.5, -1.0].sample
    game.total_line = 2.5
    game.home_edge = rand(1.5..5.5)
  end
  create_sample_report(g, "#{home} 승")
end

# 6. Create Baseball Games (KBO/MLB)
baseball_today = [
  ["LG", "SSG", "KBO"],
  ["KIA", "DOO", "KBO"]
]

baseball_today.each_with_index do |(away, home, league), i|
  g = Game.find_or_create_by!(external_id: "today_base_#{i}") do |game|
    game.sport = baseball
    game.league = league.parameterize
    game.league_name = league
    game.away_team = away; game.home_team = home
    game.away_abbr = away; game.home_abbr = home
    game.game_date = Time.current.beginning_of_day + 18.hours + (i * 30).minutes
    game.status = "scheduled"
    game.home_spread = -1.5
    game.total_line = 9.5
    game.home_edge = rand(3.0..7.0)
  end
  create_sample_report(g, "#{home} 승")
end

# 7. Create Some Insights
Insight.find_or_create_by!(title: "NBA 플레이오프 레이스 분석") do |i|
  i.sport = basketball
  i.category = "league_trends"
  i.status = "published"
  i.published_at = Time.current - 1.hour
  i.content = "현재 서부 컨퍼런스의 순위 싸움이 치열합니다. 특히 6위와 10위 사이의 격차가 2경기에 불과하여 매 경기가 결승전과 같습니다."
end

puts "🎉 Data Pumping Complete!"
puts "Games: #{Game.count}"
puts "Reports: #{Report.count}"
puts "Insights: #{Insight.count}"
