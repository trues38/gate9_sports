# frozen_string_literal: true

namespace :report do
  # LLM 기반 보고서 생성 (최종 템플릿 적용)
  desc "Generate LLM-powered report for a single game"
  task :generate_llm, [:game_id] => :environment do |_, args|
    require 'json'

    game = Game.find(args[:game_id])
    puts "🤖 LLM 보고서 생성: #{game.away_abbr} @ #{game.home_abbr}"

    # Load all data
    advanced_stats = WeaknessPrediction.load_advanced_stats
    team_trends = load_team_trends
    analyst_weights = AnalystWeight.all.index_by(&:analyst_name)
    global_triggers = fetch_global_triggers
    team_regimes = fetch_team_regimes

    # Detect triggers
    WeaknessPrediction.detect_triggers_for_game(game)
    preds = WeaknessPrediction.where(game: game)

    # Build data for LLM
    game_data = build_game_data(game, advanced_stats, team_trends, preds, global_triggers, team_regimes, analyst_weights)

    # Generate with LLM
    report_content = generate_with_llm(game_data)

    if report_content
      # Save to Report model
      report = Report.find_or_initialize_by(game: game)
      report.update!(
        title: "#{game.away_abbr} @ #{game.home_abbr}: #{extract_pick_summary(report_content)}",
        content: report_content,
        pick: extract_pick(report_content),
        confidence: extract_confidence(report_content),
        status: 'published',
        published_at: Time.current
      )
      puts "✅ 저장됨: Report ##{report.id}"
      puts report_content
    else
      puts "❌ LLM 생성 실패"
    end
  end

  desc "Generate LLM reports for all today's games with triggers"
  task daily_llm: :environment do
    require 'json'

    today = Date.current
    games = Game.where('DATE(game_date) = ?', today).order(:game_date)

    if games.empty?
      puts "오늘 경기 없음"
      exit
    end

    # Load data once
    advanced_stats = WeaknessPrediction.load_advanced_stats
    team_trends = load_team_trends
    analyst_weights = AnalystWeight.all.index_by(&:analyst_name)
    global_triggers = fetch_global_triggers
    team_regimes = fetch_team_regimes

    # [G9Engine] Run quantitative engine for all today's games
    # Neo4j가 다운되어 있어도 LLM 파이프라인은 계속 동작함
    engine_data = fetch_engine_data(today)
    if engine_data
      puts "🔢 G9Engine 분석 완료: ML #{engine_data[:ml].count}개, Spread #{engine_data[:spread].count}개, Pickem #{engine_data[:pickem].count}개, Total #{engine_data[:total].count}개"
    else
      puts "⚠️  G9Engine 데이터 없음 (Neo4j 미연결) - LLM 단독 실행"
    end

    # Detect triggers for all games
    games.each { |g| WeaknessPrediction.detect_triggers_for_game(g) }

    # Generate reports only for games with triggers
    games_with_triggers = games.select { |g| WeaknessPrediction.where(game: g).exists? }

    puts "📊 오늘 경기: #{games.count}개, 트리거 감지: #{games_with_triggers.count}개"
    puts "=" * 60

    games_with_triggers.each_with_index do |game, idx|
      puts "\n[#{idx + 1}/#{games_with_triggers.count}] #{game.away_abbr} @ #{game.home_abbr}"

      preds = WeaknessPrediction.where(game: game)

      # 이 경기의 G9Engine 픽 추출
      game_engine_picks = extract_engine_picks_for_game(engine_data, game)

      game_data = build_game_data(game, advanced_stats, team_trends, preds, global_triggers, team_regimes, analyst_weights, game_engine_picks)

      report_content = generate_with_llm(game_data)

      if report_content
        report = Report.find_or_initialize_by(game: game)

        # 피드백 루프용: 트리거 기록
        trigger_used = game.home_edge.presence || game.away_edge.presence
        preds = WeaknessPrediction.where(game: game)
        detected_triggers = preds.pluck(:trigger_type)

        # G9Engine 데이터를 structured_data에 포함
        structured = {
          trigger: trigger_used,
          detected_triggers: detected_triggers,
          confidence_at_publish: extract_confidence(report_content),
          line_at_publish: { spread: game.home_spread, total: game.total_line }
        }
        structured[:g9_engine] = game_engine_picks if game_engine_picks.present?

        report.update!(
          title: "#{game.away_abbr} @ #{game.home_abbr}: #{extract_pick_summary(report_content)}",
          content: report_content,
          pick: extract_pick(report_content),
          confidence: extract_confidence(report_content),
          status: 'published',
          published_at: Time.current,
          structured_data: structured.to_json
        )

        engine_note = game_engine_picks.present? ? " | Engine: #{engine_summary_note(game_engine_picks)}" : ""
        puts "  ✅ Report ##{report.id} 저장됨 (trigger: #{trigger_used || 'none'}#{engine_note})"
      else
        puts "  ❌ 생성 실패"
      end

      sleep 2 # Rate limiting
    end

    puts "\n" + "=" * 60
    puts "✅ LLM 보고서 생성 완료"
  end

  desc "Generate comprehensive daily analysis report (Triggers + CONTRARIAN)"
  task daily: :environment do
    require 'json'
    require 'net/http'

    today = Date.current
    # NBA만 필터 (sport_id = 1)
    games = Game.where(sport_id: 1).where('DATE(game_date) = ?', today).order(:game_date)

    if games.empty?
      puts "오늘 경기 없음"
      exit
    end

    # Load all data
    advanced_stats = WeaknessPrediction.load_advanced_stats
    team_trends = load_team_trends
    analyst_weights = AnalystWeight.all.index_by(&:analyst_name)
    global_triggers = fetch_global_triggers
    team_regimes = fetch_team_regimes

    # Detect triggers
    games.each { |g| WeaknessPrediction.detect_triggers_for_game(g) }

    # Generate report
    report = generate_comprehensive_report(
      games, advanced_stats, team_trends, analyst_weights, global_triggers, team_regimes
    )

    puts report

    # Save to file
    report_path = Rails.root.join("tmp", "reports", "#{today}.md")
    FileUtils.mkdir_p(report_path.dirname)
    File.write(report_path, report)
    puts "\n📄 저장: #{report_path}"
  end

  desc "Evaluate yesterday's predictions"
  task evaluate: :environment do
    yesterday = Date.current - 1
    games = Game.where('DATE(game_date) = ?', yesterday)
                .where(status: ['finished', 'Final'])

    if games.empty?
      puts "어제 완료된 경기 없음"
      exit
    end

    puts "📊 어제 경기 결과 평가 (#{yesterday}):"
    puts "-" * 50

    total = 0
    hits = 0

    games.each do |game|
      preds = WeaknessPrediction.where(game: game, evaluated_at: nil)
      next if preds.empty?

      game_result = game.game_result
      unless game_result&.spread_result.present?
        puts "  ⚠️ #{game.away_abbr} @ #{game.home_abbr}: 결과 없음"
        next
      end

      preds.each do |pred|
        pred.evaluate_outcome(game_result)
        total += 1
        hits += 1 if pred.hit?

        status = pred.hit? ? "✅ HIT" : "❌ MISS"
        puts "  #{status} #{pred.team} #{pred.trigger_type}"
      end
    end

    if total > 0
      hit_rate = (hits.to_f / total * 100).round(1)
      puts "\n📈 어제 결과: #{hits}/#{total} (#{hit_rate}%)"
    end
  end

  desc "Record results for finished games (자동 결과 기록)"
  task record_results: :environment do
    require 'net/http'
    require 'json'

    puts "📊 경기 결과 기록 시작..."

    # ESPN ↔ DB 약어 매핑
    abbr_map = {
      'WSH' => 'WAS', 'WAS' => 'WAS',
      'GS' => 'GSW', 'GSW' => 'GSW',
      'NO' => 'NOP', 'NOP' => 'NOP',
      'NY' => 'NYK', 'NYK' => 'NYK',
      'SA' => 'SAS', 'SAS' => 'SAS',
      'UTAH' => 'UTA', 'UTA' => 'UTA'
    }

    # 결과 미기록 + 발행된 보고서 찾기
    reports = Report.where(result: nil, status: 'published')
                    .joins(:game)
                    .where("games.game_date < ?", Time.current)

    if reports.empty?
      puts "   기록할 보고서 없음"
      return
    end

    # ESPN scoreboard (날짜 없이 = 오늘 경기)
    uri = URI("https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard")
    response = Net::HTTP.get(uri)
    espn_data = JSON.parse(response)

    recorded = 0
    reports.find_each do |report|
      game = report.game

      # ESPN에서 경기 결과 가져오기
      begin
        event = espn_data['events']&.find do |e|
          comp = e['competitions']&.first
          next unless comp
          home = comp['competitors']&.find { |c| c['homeAway'] == 'home' }
          away = comp['competitors']&.find { |c| c['homeAway'] == 'away' }

          espn_home = home&.dig('team', 'abbreviation')
          espn_away = away&.dig('team', 'abbreviation')

          # 약어 변환 후 비교
          db_home = abbr_map[espn_home] || espn_home
          db_away = abbr_map[espn_away] || espn_away

          db_home == game.home_abbr && db_away == game.away_abbr
        end

        next unless event

        comp = event['competitions'].first
        status = event.dig('status', 'type', 'completed')
        next unless status  # 경기 미종료

        home_team = comp['competitors'].find { |c| c['homeAway'] == 'home' }
        away_team = comp['competitors'].find { |c| c['homeAway'] == 'away' }

        home_score = home_team['score'].to_i
        away_score = away_team['score'].to_i

        # 결과 판정
        pick = report.pick&.upcase
        if pick.nil? || pick.include?('PASS')
          report.update!(result: 'push', result_note: 'PASS - no bet')
        else
          winner = home_score > away_score ? game.home_abbr : game.away_abbr

          # 스프레드 판정 (픽에 팀명이 포함된 경우)
          spread_result = nil
          if game.home_spread.present?
            home_spread_result = home_score + game.home_spread - away_score
            if pick.include?(game.home_abbr)
              spread_result = home_spread_result > 0 ? 'win' : (home_spread_result < 0 ? 'loss' : 'push')
            elsif pick.include?(game.away_abbr)
              spread_result = home_spread_result < 0 ? 'win' : (home_spread_result > 0 ? 'loss' : 'push')
            end
          end

          # O/U 판정
          ou_result = nil
          if pick.include?('OVER') && game.total_line.present?
            total = home_score + away_score
            ou_result = total > game.total_line ? 'win' : (total < game.total_line ? 'loss' : 'push')
          elsif pick.include?('UNDER') && game.total_line.present?
            total = home_score + away_score
            ou_result = total < game.total_line ? 'win' : (total > game.total_line ? 'loss' : 'push')
          end

          # 최종 결과 (스프레드 > O/U > 승패)
          final_result = spread_result || ou_result || (pick.include?(winner) ? 'win' : 'loss')

          report.update!(
            result: final_result,
            actual_home_score: home_score,
            actual_away_score: away_score,
            result_note: "#{away_score}-#{home_score}, spread: #{spread_result}, o/u: #{ou_result}",
            result_recorded_at: Time.current
          )
        end

        recorded += 1
        emoji = report.result == 'win' ? '✅' : (report.result == 'loss' ? '❌' : '➖')
        puts "   #{emoji} #{game.away_abbr}@#{game.home_abbr}: #{report.pick} → #{report.result}"

      rescue => e
        puts "   ⚠️ #{game.away_abbr}@#{game.home_abbr}: #{e.message}"
      end
    end

    puts "📊 결과 기록 완료: #{recorded}개"
  end

  desc "Full daily cycle"
  task cycle: :environment do
    puts "🔄 Daily Report Cycle"
    puts "=" * 60

    puts "\n[1/5] 데이터 수집..."
    Rake::Task["nba:fetch_odds"].invoke rescue puts "  - odds: skip"
    Rake::Task["nba:fetch_advanced_stats"].invoke rescue puts "  - advanced_stats: skip"
    Rake::Task["nba:fetch_team_trends"].invoke rescue puts "  - trends: skip"

    puts "\n[2/5] 트리거 감지..."
    Rake::Task["weakness:detect"].invoke

    puts "\n[3/5] 리포트 생성..."
    Rake::Task["report:daily"].invoke

    puts "\n[4/4] 전일 결과 평가..."
    Rake::Task["report:evaluate"].invoke rescue puts "  (평가할 결과 없음)"

    puts "\n" + "=" * 60
    puts "✅ Daily cycle complete"
  end

  private

  def load_team_trends
    path = Rails.root.join("tmp", "team_trends.json")
    return {} unless File.exist?(path)
    JSON.parse(File.read(path))
  rescue
    {}
  end

  # 트리거 승률 - 하드코딩 (Neo4j 제거)
  # 백테스트 기반 검증된 수치
  def fetch_global_triggers
    {
      'B2B' => { hit_rate: 54, signal: 'NEUTRAL' },
      '3IN4' => { hit_rate: 52.6, signal: 'NEUTRAL' },
      'BAD_MATCHUP_DEFENSE' => { hit_rate: 61.5, signal: 'MODERATE' },
      'BAD_MATCHUP_OFFENSE' => { hit_rate: 58, signal: 'MODERATE' },
      'REVENGE' => { hit_rate: 55, signal: 'NEUTRAL' },
      'REST_ADVANTAGE' => { hit_rate: 56, signal: 'NEUTRAL' }
    }
  end

  # TeamRegime 제거 - 사용 빈도 낮음, 단순화
  def fetch_team_regimes
    {}
  end

  def generate_comprehensive_report(games, advanced_stats, team_trends, analyst_weights, global_triggers, team_regimes)
    today = Date.current
    report = []

    report << "=" * 70
    report << "🏀 Gate9 Sports - Daily Analysis Report"
    report << "📅 #{today.strftime('%Y-%m-%d')} (KST)"
    report << "=" * 70
    report << ""

    # Section 1: CONTRARIAN 분석가 (단순화)
    report << "## 📊 CONTRARIAN 분석가"
    aw = analyst_weights['CONTRARIAN']
    if aw
      report << "- 정확도: #{(aw.accuracy * 100).round(1)}%"
      report << "- 가중치: +#{aw.weight}"
      report << "- 역할: 메인 시그널 (빅 언더독 커버 경향)"
    end
    report << ""

    # Section 2: Global Trigger Hit Rates
    report << "## 🎯 검증된 트리거 (전체 히트율)"
    report << ""
    sorted_triggers = global_triggers.sort_by { |_, v| -(v[:hit_rate] || 0) }
    sorted_triggers.each do |trigger, data|
      emoji = data[:signal] == 'STRONG' ? '🔥' : (data[:signal] == 'MODERATE' ? '✅' : '➖')
      report << "- #{emoji} **#{trigger}**: #{data[:hit_rate]}% [#{data[:signal]}]"
    end
    report << ""

    # Section 3: Game Analysis
    report << "## 🏀 오늘 경기 분석"
    report << ""

    recommendations = []

    games.each do |g|
      preds = WeaknessPrediction.where(game: g)
      home_stats = advanced_stats[g.home_abbr] || {}
      away_stats = advanced_stats[g.away_abbr] || {}
      home_trends = team_trends[g.home_abbr] || {}
      away_trends = team_trends[g.away_abbr] || {}

      report << "-" * 70
      report << "### #{g.away_abbr} @ #{g.home_abbr}"
      report << "⏰ #{g.game_date.in_time_zone('Asia/Seoul').strftime('%H:%M')} KST"
      if g.home_spread
        report << "📈 라인: #{g.home_abbr} #{g.home_spread} / O/U #{g.total_line}"
      end
      report << ""

      # Team Stats Comparison
      report << "**팀 비교:**"
      report << "| | #{g.away_abbr} | #{g.home_abbr} |"
      report << "|---|---|---|"
      report << "| 전적 | #{away_trends['record'] || 'N/A'} | #{home_trends['record'] || 'N/A'} |"
      report << "| 최근 5경기 | #{away_trends['current_streak'] || 'N/A'} | #{home_trends['current_streak'] || 'N/A'} |"
      report << "| OFF RTG | ##{away_stats['off_rank']} (#{away_stats['off_rtg']}) | ##{home_stats['off_rank']} (#{home_stats['off_rtg']}) |"
      report << "| DEF RTG | ##{away_stats['def_rank']} (#{away_stats['def_rtg']}) | ##{home_stats['def_rank']} (#{home_stats['def_rtg']}) |"
      report << "| ATS | #{away_trends.dig('ats', 'record') || 'N/A'} | #{home_trends.dig('ats', 'record') || 'N/A'} |"
      report << ""

      # TeamRegime 제거 - 단순화

      # Active Triggers
      if preds.any?
        report << "**🎯 활성 트리거:**"
        best_confidence = 0
        best_pick = nil

        preds.each do |p|
          gt = global_triggers[p.trigger_type] || {}
          hit_rate = gt[:hit_rate] || 50
          signal = gt[:signal] || 'NEUTRAL'
          emoji = signal == 'STRONG' ? '🔥' : (signal == 'MODERATE' ? '✅' : '➖')

          report << "- #{emoji} **#{p.trigger_type}** on #{p.team}"
          report << "  - #{p.trigger_detail}"
          report << "  - 히트율: #{hit_rate}% [#{signal}]"

          if hit_rate >= 60 && hit_rate > best_confidence
            opp = (p.team == g.home_team) ? g.away_abbr : g.home_abbr
            best_pick = opp
            best_confidence = hit_rate
          end
        end
        report << ""

        if best_pick
          report << "**📌 트리거 시그널: #{best_pick} (#{best_confidence.round(0)}%)**"
          recommendations << {
            game: "#{g.away_abbr}@#{g.home_abbr}",
            pick: best_pick,
            confidence: best_confidence,
            trigger: preds.map(&:trigger_type).join('+')
          }
        end
      else
        report << "**트리거: 없음**"
      end

      # FINAL VERDICT - 단일 최적 픽
      contrarian_pick = generate_contrarian_pick(g)

      # 게임 데이터 구조 생성
      game_data = {
        home: g.home_abbr,
        away: g.away_abbr,
        home_full: g.home_team,
        away_full: g.away_team,
        spread: g.home_spread,
        total: g.total_line
      }
      team_stats_data = {
        home: { net_rtg: home_stats['net_rtg'], off_rank: home_stats['off_rank'], def_rank: home_stats['def_rank'] },
        away: { net_rtg: away_stats['net_rtg'], off_rank: away_stats['off_rank'], def_rank: away_stats['def_rank'] }
      }

      # 트리거 정보
      best_trigger_info = nil
      if preds.any?
        best_pred = preds.max_by { |p| (global_triggers[p.trigger_type] || {})[:hit_rate] || 0 }
        if best_pred
          gt = global_triggers[best_pred.trigger_type] || {}
          best_trigger_info = {
            type: best_pred.trigger_type,
            hit_rate: gt[:hit_rate] || 50,
            team: best_pred.team  # 약점 팀
          }
        end
      end

      # 최적 픽 결정 (새 로직)
      best_pick_data = { best_pick: best_pick }
      contrarian_data = contrarian_pick[:pick] != 'PASS' ? contrarian_pick : nil

      final_pick = determine_best_pick_simple(
        game_data, team_stats_data, best_trigger_info, contrarian_data
      )

      stars = "⭐" * final_pick[:confidence] + "☆" * (5 - final_pick[:confidence])

      report << ""
      report << "**🏆 PICK: #{final_pick[:pick]}** (#{final_pick[:type]}) #{stars}"
      report << "   └ #{final_pick[:reason]}"
      report << ""
    end

    # Summary
    if recommendations.any?
      report << "=" * 70
      report << "## 📋 오늘의 트리거 시그널 요약"
      report << ""
      recommendations.sort_by { |r| -r[:confidence] }.each do |r|
        emoji = r[:confidence] >= 70 ? '🔥' : '✅'
        report << "#{emoji} **#{r[:game]}**: #{r[:pick]} (#{r[:confidence].round(0)}%) [#{r[:trigger]}]"
      end
    end

    report << ""
    report << "=" * 70
    report << "⚠️ 백테스트 기반 참고용 - 책임 베팅"
    report << "📊 데이터: SQLite + ESPN + NBA.com"
    report << "=" * 70

    report.join("\n")
  end

  # CONTRARIAN 단일 분석 (단순화)
  def generate_contrarian_pick(game)
    if game.home_spread && game.home_spread.abs >= 7
      underdog = game.home_spread < 0 ? game.away_abbr : game.home_abbr
      { pick: underdog, reason: "빅 언더독 커버 경향 (#{game.home_spread.abs}pt)" }
    else
      { pick: 'PASS', reason: "스프레드 7pt 미만" }
    end
  end

  # 단일 최적 픽 (간소화 버전 - daily report용)
  def determine_best_pick_simple(game, team_stats, best_trigger, contrarian)
    candidates = []

    # 1. CONTRARIAN 스프레드
    if contrarian
      spread_val = game[:spread]&.abs || 0
      confidence = case spread_val
        when 15.. then 4
        when 10..14 then 3
        when 7..9 then 2
        else 1
      end
      candidates << {
        type: 'SPREAD',
        pick: "#{contrarian[:pick]} +#{spread_val}",
        confidence: confidence,
        reason: "CONTRARIAN #{spread_val}pt 언더독"
      }
    end

    # 2. BAD_MATCHUP 트리거 → ML
    if best_trigger && best_trigger[:type]&.include?('BAD_MATCHUP')
      hit_rate = best_trigger[:hit_rate] || 50
      # 트리거 대상의 반대팀이 유리 (full team name으로 비교)
      trigger_team = best_trigger[:team]
      opponent = (trigger_team == game[:home_full]) ? game[:away] : game[:home]
      confidence = hit_rate >= 65 ? 4 : (hit_rate >= 60 ? 3 : 2)
      candidates << {
        type: 'ML',
        pick: opponent,
        confidence: confidence,
        reason: "#{best_trigger[:type]} #{hit_rate}%"
      }
    end

    # 3. B2B/3IN4 → 상대편 유리
    if best_trigger && (best_trigger[:type]&.include?('B2B') || best_trigger[:type]&.include?('3IN4'))
      trigger_team = best_trigger[:team]
      opponent = (trigger_team == game[:home_full]) ? game[:away] : game[:home]
      candidates << {
        type: 'SPREAD',
        pick: "#{opponent} 커버",
        confidence: 2,
        reason: "#{best_trigger[:type]} 피로"
      }
    end

    # 4. O/U - 스탯 기반
    home_off = team_stats[:home][:off_rank].to_i rescue 99
    home_def = team_stats[:home][:def_rank].to_i rescue 99
    away_off = team_stats[:away][:off_rank].to_i rescue 99
    away_def = team_stats[:away][:def_rank].to_i rescue 99

    if (home_off <= 10 && away_off <= 10) && (home_def >= 20 || away_def >= 20)
      candidates << { type: 'O/U', pick: "OVER #{game[:total]}", confidence: 2, reason: "양팀 공격력" }
    elsif (home_def <= 10 && away_def <= 10)
      candidates << { type: 'O/U', pick: "UNDER #{game[:total]}", confidence: 2, reason: "양팀 수비력" }
    end

    # 5. 폴백: NET RTG
    if candidates.empty?
      home_net = team_stats[:home][:net_rtg].to_f rescue 0
      away_net = team_stats[:away][:net_rtg].to_f rescue 0
      favored = home_net >= away_net ? game[:home] : game[:away]
      candidates << { type: 'ML', pick: favored, confidence: 1, reason: "NET RTG 기반" }
    end

    candidates.max_by { |c| c[:confidence] } || { type: 'ML', pick: game[:home], confidence: 1, reason: "홈팀" }
  end

  # LLM 보고서 생성 헬퍼 메서드들
  def build_game_data(game, advanced_stats, team_trends, triggers, global_triggers, team_regimes, analyst_weights, engine_picks = nil)
    home_stats = advanced_stats[game.home_abbr] || {}
    away_stats = advanced_stats[game.away_abbr] || {}
    home_trends = team_trends[game.home_abbr] || {}
    away_trends = team_trends[game.away_abbr] || {}

    # Build trigger info
    trigger_info = triggers.map do |t|
      gt = global_triggers[t.trigger_type] || {}
      {
        type: t.trigger_type,
        team: t.team,
        detail: t.trigger_detail,
        hit_rate: gt[:hit_rate] || 50,
        signal: gt[:signal] || 'NEUTRAL'
      }
    end

    # Best trigger signal
    best_trigger = trigger_info.max_by { |t| t[:hit_rate] }
    best_pick = nil
    if best_trigger && best_trigger[:hit_rate] >= 60
      best_pick = (best_trigger[:team] == game.home_team) ? game.away_abbr : game.home_abbr
    end

    # CONTRARIAN 픽 생성 (단순화)
    contrarian_pick = generate_contrarian_pick(game)

    {
      game: {
        away: game.away_abbr,
        home: game.home_abbr,
        date: game.game_date.in_time_zone('Asia/Seoul').strftime('%Y-%m-%d'),
        time: game.game_date.in_time_zone('Asia/Seoul').strftime('%H:%M'),
        spread: game.home_spread,
        total: game.total_line,
        venue: game.venue || 'TBD'
      },
      triggers: trigger_info,
      best_trigger: best_trigger,
      best_pick: best_pick,
      contrarian_pick: contrarian_pick,
      engine_picks: engine_picks,
      team_stats: {
        home: {
          record: home_trends['record'] || 'N/A',
          streak: home_trends['current_streak'] || 'N/A',
          off_rtg: home_stats['off_rtg'],
          off_rank: home_stats['off_rank'],
          def_rtg: home_stats['def_rtg'],
          def_rank: home_stats['def_rank'],
          net_rtg: home_stats['net_rtg'],
          ats: home_trends.dig('ats', 'record') || 'N/A'
        },
        away: {
          record: away_trends['record'] || 'N/A',
          streak: away_trends['current_streak'] || 'N/A',
          off_rtg: away_stats['off_rtg'],
          off_rank: away_stats['off_rank'],
          def_rtg: away_stats['def_rtg'],
          def_rank: away_stats['def_rank'],
          net_rtg: away_stats['net_rtg'],
          ats: away_trends.dig('ats', 'record') || 'N/A'
        }
      }
    }
  end

  def generate_with_llm(game_data)
    # Try LLM first, fallback to template-based
    if ENV['OPENROUTER_API_KEY'].present?
      client = OpenrouterClient.new
      system_prompt = build_system_prompt
      user_prompt = build_user_prompt(game_data)
      result = client.chat(user_prompt, system: system_prompt)
      return result.strip if result.present?
    end

    # Fallback: Generate report using template directly
    generate_template_report(game_data)
  rescue => e
    puts "  ⚠️ LLM Error: #{e.message}, using template fallback"
    generate_template_report(game_data)
  end

  def generate_template_report(data)
    g = data[:game]
    triggers = data[:triggers]
    best_trigger = data[:best_trigger]
    contrarian = data[:contrarian_pick]

    report = []

    # HEADER
    report << "# #{g[:away]} @ #{g[:home]}"
    report << ""
    report << "📅 #{g[:date]} #{g[:time]} KST"
    if g[:spread]
      report << "📈 #{g[:home]} #{g[:spread] > 0 ? '+' : ''}#{g[:spread]} | O/U #{g[:total]}"
    end
    report << ""
    report << "---"
    report << ""

    # TRIGGER SIGNAL
    report << "## 🎯 트리거 시그널"
    report << ""

    if best_trigger && best_trigger[:hit_rate] >= 60
      emoji = best_trigger[:signal] == 'STRONG' ? '🔥' : '✅'
      weak_team = best_trigger[:team]
      strong_team = (weak_team == g[:home]) ? g[:away] : g[:home]

      report << "╔═══════════════════════════════════════════════════════════╗"
      report << "║  #{emoji} **#{best_trigger[:type]}** 감지"
      report << "║  ─────────────────────────────────────────────────────"
      report << "║  #{weak_team}: #{best_trigger[:detail]}"
      report << "║"
      report << "║  📊 백테스트 히트율: **#{best_trigger[:hit_rate]}%** [#{best_trigger[:signal]}]"
      report << "║  📌 추천: **#{data[:best_pick]}** 승리 유리"
      report << "╚═══════════════════════════════════════════════════════════╝"
    else
      report << "ℹ️ 이 경기에서 유의미한 트리거가 감지되지 않았습니다."
      report << "→ 분석가 패널 의견을 참고하세요."
    end

    # Additional triggers
    other_triggers = triggers.select { |t| t != best_trigger && t[:hit_rate] >= 50 }
    if other_triggers.any?
      report << ""
      report << "### 추가 감지 트리거"
      other_triggers.each do |t|
        emoji = t[:signal] == 'STRONG' ? '🔥' : (t[:signal] == 'MODERATE' ? '✅' : '➖')
        report << "- #{emoji} **#{t[:type]}** on #{t[:team]} (#{t[:hit_rate]}%)"
      end
    end

    report << ""
    report << "---"
    report << ""

    # TEAM COMPARISON
    report << "## 📊 팀 비교"
    report << ""
    report << "| 항목 | #{g[:away]} | #{g[:home]} |"
    report << "|------|--------|--------|"
    report << "| **전적** | #{data[:team_stats][:away][:record]} | #{data[:team_stats][:home][:record]} |"
    report << "| **최근 5경기** | #{data[:team_stats][:away][:streak]} | #{data[:team_stats][:home][:streak]} |"
    report << "| **OFF RTG** | ##{data[:team_stats][:away][:off_rank]} (#{data[:team_stats][:away][:off_rtg]}) | ##{data[:team_stats][:home][:off_rank]} (#{data[:team_stats][:home][:off_rtg]}) |"
    report << "| **DEF RTG** | ##{data[:team_stats][:away][:def_rank]} (#{data[:team_stats][:away][:def_rtg]}) | ##{data[:team_stats][:home][:def_rank]} (#{data[:team_stats][:home][:def_rtg]}) |"
    report << "| **NET RTG** | #{data[:team_stats][:away][:net_rtg]} | #{data[:team_stats][:home][:net_rtg]} |"

    # Team weaknesses 제거 - 단순화

    report << ""
    report << "---"
    report << ""

    # CONTRARIAN 분석 (단순화)
    report << "## 🔄 CONTRARIAN 분석"
    report << ""

    contrarian_pick = nil
    if g[:spread] && g[:spread].abs >= 7
      contrarian_pick = g[:spread] < 0 ? g[:away] : g[:home]
      report << "**픽:** #{contrarian_pick}"
      report << "**논거:** 빅 언더독 커버 경향 (#{g[:spread].abs}pt)"
    else
      report << "**픽:** PASS"
      report << "**논거:** 스프레드 7pt 미만"
    end

    report << ""
    report << "---"
    report << ""

    # FINAL VERDICT - 단일 최적 픽
    report << "## 🏆 Final Verdict"
    report << ""

    # 최적 픽 결정
    best_pick = determine_best_pick(data, best_trigger, contrarian, g)
    stars = "⭐" * best_pick[:confidence] + "☆" * (5 - best_pick[:confidence])

    report << "╔═══════════════════════════════════════════════════════════╗"
    report << "║                                                           ║"
    report << "║   📌 PICK: **#{best_pick[:pick]}** (#{best_pick[:type]})"
    report << "║   #{stars} (#{best_pick[:confidence]}/5)"
    report << "║                                                           ║"
    report << "║   💡 #{best_pick[:reason]}"
    report << "║                                                           ║"
    report << "╚═══════════════════════════════════════════════════════════╝"

    report << ""
    report << "---"
    report << ""
    report << "*G9 Sports Intelligence*"
    report << "*트리거 + CONTRARIAN 시스템*"
    report << "*Generated: #{Time.current.in_time_zone('Asia/Seoul').strftime('%Y-%m-%d %H:%M')} KST*"
    report << ""
    report << "⚠️ 백테스트 기반 참고용 분석입니다. 최종 베팅 결정은 본인 책임입니다."

    report.join("\n")
  end

  def build_system_prompt
    <<~PROMPT
      # G9 Top Analyst - Chain of Analyst Thought (CAT)

      너는 15년 경력의 프로 NBA 분석가다.
      매 경기를 분석할 때 반드시 아래 6단계 사고 과정을 순서대로 따른다.
      **이 순서를 절대 건너뛰거나 바꾸지 마라.**

      ---

      ## 필수 사고 프로세스 (6단계)

      ### Step 1: First Glance (첫 인상) 🎯
      경기를 처음 봤을 때 드는 직관적 생각을 서술해.
      - 이 매치업의 내러티브는? (라이벌? 리벤지? 미스매치?)
      - 양 팀 시즌 맥락은? (상승세? 부상?)
      - 직감적으로 누가 이길 것 같아?
      - 라인이 합리적으로 보여?

      ### Step 2: Line Decoding (라인 해석) 📊
      스프레드/O-U가 왜 이렇게 설정됐는지 분석해.
      - 이 숫자에 무엇이 반영됐나?
      - 시장이 과대평가한 요소는?
      - 시장이 과소평가한 요소는?

      ### Step 3: Edge Hunting (엣지 탐색) 🔍
      체크리스트를 체계적으로 스캔해:
      - □ 부상: 핵심 선수 OUT? 영향도?
      - □ B2B/3in4: 피로도?
      - □ 최근 폼: L5, L10?
      - □ H2H: 상대 전적 패턴?
      - □ 트리거: 검증된 시스템 신호?

      ### Step 4: Matchup Deep Dive (매치업 분석) ⚔️
      전술적 상성을 분석해.
      - 각 팀의 핵심 무기는?
      - 상대는 이걸 어떻게 막나?
      - 결정적 미스매치가 있나?

      ### Step 5: Devil's Advocate (반대 논거) 😈
      네 분석의 약점을 찾아.
      - 이 분석이 틀릴 시나리오는?
      - 반대 베팅의 논거는?
      - 놓친 변수가 있나?

      ### Step 6: Synthesis (종합 판단) ✅
      모든 분석을 종합해 결론 도출.
      - 최종 픽과 신뢰도
      - 핵심 근거 3가지
      - 리스크 요인 2가지

      ---

      ## 출력 형식 (반드시 준수)

      ```
      # {AWAY} @ {HOME}
      📅 {DATE} {TIME} KST | 📈 {LINE}

      ---

      ## 1️⃣ First Glance
      [내면의 독백 형식으로 첫 인상 서술]

      ## 2️⃣ Line Decoding
      [라인 해석 - 왜 이 숫자인지]

      ## 3️⃣ Edge Hunting
      | 요소 | 체크 | 내용 |
      |------|------|------|
      | 부상 | ✅/❌ | ... |
      | B2B | ✅/❌ | ... |
      | 폼 | ✅/❌ | ... |
      | 트리거 | ✅/❌ | ... |

      ## 4️⃣ Matchup Analysis
      [전술적 매치업 분석]

      ## 5️⃣ Devil's Advocate
      [반대 논거 - 내가 틀릴 수 있는 이유]

      ## 6️⃣ Final Verdict
      ╔═══════════════════════════════════════════════════════════╗
      ║  📌 PICK: **{PICK}**                                      ║
      ║  🎯 신뢰도: {★★★☆☆}                                       ║
      ║  💡 핵심: {ONE_LINE}                                      ║
      ╚═══════════════════════════════════════════════════════════╝

      **핵심 근거:**
      1. ...
      2. ...
      3. ...

      **리스크:**
      - ...
      - ...
      ```

      ---

      ## 절대 규칙

      1. **한국어**로 작성
      2. **6단계 순서** 반드시 준수 (건너뛰기 금지)
      3. 각 단계에서 **실제 사고 과정**을 보여줘 (템플릿 채우기 X)
      4. First Glance는 **"내면의 독백"** 형식 사용
      5. 데이터가 없으면 "데이터 없음"이라고 명시
      6. 신뢰도는 ★☆☆☆☆ ~ ★★★★★ (5단계)
      7. PASS도 정당한 결론 - 엣지 없으면 PASS 권장
    PROMPT
  end

  def build_user_prompt(data)
    triggers_text = data[:triggers].map do |t|
      "- #{t[:type]} on #{t[:team]}: #{t[:detail]} (히트율 #{t[:hit_rate]}%, #{t[:signal]})"
    end.join("\n")

    engine_section = build_engine_prompt_section(data[:engine_picks])

    <<~PROMPT
      아래 경기를 CAT 6단계로 분석해줘.

      ---

      ## 경기 정보
      **#{data[:game][:away]} @ #{data[:game][:home]}**
      - 일시: #{data[:game][:date]} #{data[:game][:time]} KST
      - 스프레드: #{data[:game][:home]} #{data[:game][:spread]}
      - 토탈: #{data[:game][:total]}

      ---

      ## 팀 데이터

      ### #{data[:game][:away]} (원정)
      - 전적: #{data[:team_stats][:away][:record]}
      - 최근: #{data[:team_stats][:away][:streak]}
      - OFF: ##{data[:team_stats][:away][:off_rank]} (#{data[:team_stats][:away][:off_rtg]})
      - DEF: ##{data[:team_stats][:away][:def_rank]} (#{data[:team_stats][:away][:def_rtg]})
      - NET: #{data[:team_stats][:away][:net_rtg]}
      - 검증된 약점: #{data[:team_weaknesses][:away].map { |w| "#{w['trigger']}(#{w['hit_rate']}%)" }.join(', ').presence || '없음'}

      ### #{data[:game][:home]} (홈)
      - 전적: #{data[:team_stats][:home][:record]}
      - 최근: #{data[:team_stats][:home][:streak]}
      - OFF: ##{data[:team_stats][:home][:off_rank]} (#{data[:team_stats][:home][:off_rtg]})
      - DEF: ##{data[:team_stats][:home][:def_rank]} (#{data[:team_stats][:home][:def_rtg]})
      - NET: #{data[:team_stats][:home][:net_rtg]}
      - 검증된 약점: #{data[:team_weaknesses][:home].map { |w| "#{w['trigger']}(#{w['hit_rate']}%)" }.join(', ').presence || '없음'}

      ---

      ## 감지된 트리거 (백테스트 검증)
      #{triggers_text.presence || "감지된 트리거 없음"}

      #{data[:best_trigger] ? "**최고 시그널**: #{data[:best_trigger][:type]} (#{data[:best_trigger][:hit_rate]}%) → #{data[:best_pick]} 유리" : ""}

      ---
      #{engine_section}

      위 데이터를 바탕으로 CAT 6단계(First Glance → Line Decoding → Edge Hunting → Matchup → Devil's Advocate → Synthesis)를 **순서대로 빠짐없이** 수행해줘.

      특히:
      - Step 1에서는 "내면의 독백" 형식으로 첫 인상을 써줘
      - Step 3에서는 체크리스트 테이블로 엣지 요소를 스캔해줘
      - Step 3 Edge Hunting에서 G9 Engine 정량 분석 데이터를 반드시 참고해줘 (있을 경우)
      - Step 5에서는 진지하게 반대 논거를 찾아줘
      - Step 6에서는 명확한 PICK 또는 PASS 결론을 내려줘
    PROMPT
  end

  # G9Engine 프롬프트 섹션 생성
  # engine_picks가 nil이면 빈 문자열 반환 (Neo4j 미연결 시)
  def build_engine_prompt_section(engine_picks)
    return "" if engine_picks.blank?

    lines = []
    lines << "## 🔢 G9 Engine 정량 분석 (Neo4j 기반 백테스트)"
    lines << ""
    lines << "*(아래 수치는 실적 검증된 알고리즘 출력값입니다. 분석 시 참고하세요.)*"
    lines << ""

    if (ml = engine_picks[:ml]).present?
      lines << "### ML (역배 경고)"
      lines << "- 경고 수준: **#{ml[:upset_alert]}**"
      lines << "- Signal: #{ml[:signal]}"
      lines << "- 페이보릿: #{ml[:favorite]} (#{ml[:fav_side]}) / 언더독: #{ml[:underdog]} (#{ml[:dog_side]})"
      lines << "- 페이보릿 Flow: #{ml[:fav_flow]} | 언더독 Flow: #{ml[:dog_flow]}"
      lines << "- 홈 Net RTG: #{ml[:home_net_rtg]} | 어웨이 Net RTG: #{ml[:away_net_rtg]}"
      lines << "- 스프레드: #{ml[:spread]} (#{ml[:abs_spread]}pt)"
      lines << ""
    end

    if (spread = engine_picks[:spread]).present?
      lines << "### Spread (언더독 커버)"
      lines << "- Signal: **#{spread[:signal]}**"
      lines << "- 추천: #{spread[:recommended]} (#{spread[:pick_side]})"
      lines << "- 스프레드 구간: #{spread[:spread_tier]} (역사적 커버율 #{spread[:historical_cover_pct]}%)"
      lines << "- 스프레드: #{spread[:spread]}"
      lines << ""
    end

    if (pickem = engine_picks[:pickem]).present?
      lines << "### Pickem Underdog"
      lines << "- Signal: **#{pickem[:signal]}**"
      lines << "- 추천: #{pickem[:recommended]} +#{pickem[:spread]}"
      lines << "- Pickem Edge Score: #{pickem[:pickem_edge_score]}"
      lines << "- 타입: #{pickem[:pickem_type]} | Net RTG Edge: #{pickem[:net_rtg_edge]}"
      lines << ""
    end

    if (total = engine_picks[:total]).present?
      lines << "### Total (Over/Under)"
      lines << "- Signal: **#{total[:signal]}**"
      lines << "- 방향: #{total[:pick_direction]} (예상 #{total[:expected_total]} vs 라인 #{total[:total_line]})"
      lines << "- 토탈 구간: #{total[:total_tier]} | diff: #{total[:diff]}"
      lines << ""
    end

    if engine_picks[:ml].blank? && engine_picks[:spread].blank? && engine_picks[:pickem].blank? && engine_picks[:total].blank?
      lines << "*(이 경기에 대한 G9 Engine 신호 없음)*"
      lines << ""
    end

    lines << "---"
    lines.join("\n") + "\n"
  end

  # 최적 단일 픽 결정 (ML/스프레드/O-U 중 1개 + 신뢰도 1-5)
  def determine_best_pick(data, best_trigger, contrarian, game)
    team_stats = data[:team_stats]
    trigger_type = best_trigger&.dig(:type) || ''
    hit_rate = best_trigger&.dig(:hit_rate) || 0
    trigger_pick = data[:best_pick]
    contrarian_pick = contrarian && contrarian[:pick] != 'PASS' ? contrarian[:pick] : nil

    candidates = []

    # 1. CONTRARIAN 스프레드 (7pt+ 언더독)
    if contrarian_pick
      spread_val = game[:spread]&.abs || 0
      underdog_line = contrarian_pick == game[:home] ?
        "+#{game[:spread]&.abs}" : "+#{game[:spread]&.abs}"

      confidence = case spread_val
        when 15.. then 4  # 15pt+ 빅독
        when 10..14 then 3  # 10-14pt
        when 7..9 then 2   # 7-9pt
        else 1
      end

      candidates << {
        type: 'SPREAD',
        pick: "#{contrarian_pick} #{underdog_line}",
        confidence: confidence,
        reason: "CONTRARIAN #{spread_val}pt 언더독"
      }
    end

    # 2. BAD_MATCHUP 트리거 → ML
    if trigger_type.include?('BAD_MATCHUP') && trigger_pick
      confidence = hit_rate >= 65 ? 4 : (hit_rate >= 60 ? 3 : 2)
      candidates << {
        type: 'ML',
        pick: trigger_pick,
        confidence: confidence,
        reason: "#{trigger_type} #{hit_rate}%"
      }
    end

    # 3. B2B/3IN4 트리거 → 상대편 스프레드
    if (trigger_type.include?('B2B') || trigger_type.include?('3IN4')) && trigger_pick
      confidence = hit_rate >= 55 ? 2 : 1
      candidates << {
        type: 'SPREAD',
        pick: "#{trigger_pick} 커버",
        confidence: confidence,
        reason: "#{trigger_type} - 상대 피로"
      }
    end

    # 4. O/U - 팀 스탯 기반
    home_off = team_stats[:home][:off_rank].to_i
    home_def = team_stats[:home][:def_rank].to_i
    away_off = team_stats[:away][:off_rank].to_i
    away_def = team_stats[:away][:def_rank].to_i

    if (home_off <= 10 && away_off <= 10) && (home_def >= 20 || away_def >= 20)
      candidates << {
        type: 'O/U',
        pick: "OVER #{game[:total]}",
        confidence: 2,
        reason: "양팀 공격 우수 + 수비 약함"
      }
    elsif (home_def <= 10 && away_def <= 10) && (home_off >= 20 || away_off >= 20)
      candidates << {
        type: 'O/U',
        pick: "UNDER #{game[:total]}",
        confidence: 2,
        reason: "양팀 수비 우수"
      }
    end

    # 5. 폴백: NET RTG 기반 ML
    home_net = team_stats[:home][:net_rtg].to_f rescue 0
    away_net = team_stats[:away][:net_rtg].to_f rescue 0
    net_diff = (home_net - away_net).abs

    if candidates.empty?
      favored = home_net > away_net ? game[:home] : game[:away]
      confidence = net_diff >= 10 ? 2 : 1
      candidates << {
        type: 'ML',
        pick: favored,
        confidence: confidence,
        reason: "NET RTG #{favored} +#{net_diff.round(1)}"
      }
    end

    # 최고 신뢰도 픽 선택
    best = candidates.max_by { |c| c[:confidence] }
    best || { type: 'ML', pick: game[:home], confidence: 1, reason: "홈 어드밴티지" }
  end

  def extract_pick(content)
    # Look for PICK: **XXX** pattern (팀명, PASS, OVER/UNDER 등)
    match = content.match(/PICK:\s*\*\*([A-Z][A-Z0-9\s\.\-+]+)\*\*/i)
    return nil unless match

    pick = match[1].strip.upcase
    # PASS, OVER, UNDER, 팀명 등 반환
    pick.present? ? pick : nil
  end

  def extract_confidence(content)
    # Look for hit rate percentage
    match = content.match(/(\d{2,3})%/)
    return 5 if match && match[1].to_i >= 80
    return 4 if match && match[1].to_i >= 70
    return 3 if match && match[1].to_i >= 60
    2
  end

  def extract_pick_summary(content)
    # Try to extract trigger type and hit rate
    trigger_match = content.match(/🔥\s*\*\*([A-Z_]+)\*\*|✅\s*\*\*([A-Z_]+)\*\*/)
    rate_match = content.match(/히트율:\s*\*\*(\d+\.?\d*)%\*\*|(\d+)%\s*\[STRONG\]/)

    trigger = trigger_match ? (trigger_match[1] || trigger_match[2]) : nil
    rate = rate_match ? (rate_match[1] || rate_match[2]) : nil

    if trigger && rate
      trigger_short = trigger.gsub('BAD_MATCHUP_', '').gsub('_', ' ').capitalize
      "#{trigger_short} 시그널 (#{rate}%)"
    else
      "분석 보고서"
    end
  end

  # =========================================================================
  # G9Engine 통합 헬퍼 메서드
  # =========================================================================

  # G9EngineService를 호출해 오늘 전체 경기의 정량 분석 결과를 반환.
  # Neo4j가 다운됐거나 gem 미설치 시 nil 반환 (LLM 파이프라인은 계속 동작).
  #
  # @param date [Date]
  # @return [Hash, nil] { ml: [...], spread: [...], pickem: [...], total: [...] }
  def fetch_engine_data(date)
    date_str = date.strftime('%Y%m%d')
    engine = G9EngineService.new
    engine.analyze_all(date_str)
  rescue => e
    Rails.logger.warn("[G9Engine] Neo4j 연결 실패, 정량 분석 스킵: #{e.message}")
    nil
  end

  # engine_data(analyze_all 결과)에서 특정 game에 해당하는 픽들을 추출.
  # 매칭 기준: away/home 약어 조합 (예: "LAL @ BOS")
  #
  # @param engine_data [Hash, nil]
  # @param game [Game]
  # @return [Hash, nil] { ml: Hash|nil, spread: Hash|nil, pickem: Hash|nil, total: Hash|nil }
  def extract_engine_picks_for_game(engine_data, game)
    return nil if engine_data.nil?

    away = game.away_abbr.to_s.upcase
    home = game.home_abbr.to_s.upcase

    # 각 타입별로 해당 경기 픽 찾기 (away/home 매칭)
    ml_pick     = engine_data[:ml]&.find     { |p| p[:away].to_s.upcase == away && p[:home].to_s.upcase == home }
    spread_pick = engine_data[:spread]&.find { |p| p[:away].to_s.upcase == away && p[:home].to_s.upcase == home }
    pickem_pick = engine_data[:pickem]&.find { |p| p[:away].to_s.upcase == away && p[:home].to_s.upcase == home }
    total_pick  = engine_data[:total]&.find  { |p| p[:away].to_s.upcase == away && p[:home].to_s.upcase == home }

    # 모두 없으면 nil 반환 (structured_data에 불필요한 빈 키 저장 방지)
    return nil if ml_pick.nil? && spread_pick.nil? && pickem_pick.nil? && total_pick.nil?

    {
      ml:     ml_pick,
      spread: spread_pick,
      pickem: pickem_pick,
      total:  total_pick
    }
  end

  # 로그 출력용 엔진 요약 한 줄
  # @param engine_picks [Hash]
  # @return [String]
  def engine_summary_note(engine_picks)
    parts = []
    if (ml = engine_picks[:ml])
      parts << "ML:#{ml[:upset_alert]}"
    end
    if (sp = engine_picks[:spread])
      parts << "Spread:#{sp[:recommended]}(#{sp[:spread_tier]})"
    end
    if (pk = engine_picks[:pickem])
      parts << "Pickem:#{pk[:recommended]}(#{pk[:pickem_edge_score]})"
    end
    if (tot = engine_picks[:total])
      parts << "Total:#{tot[:pick_direction]}"
    end
    parts.any? ? parts.join(', ') : 'no signals'
  end
end
