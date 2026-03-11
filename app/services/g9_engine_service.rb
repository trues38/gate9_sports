# frozen_string_literal: true

# G9EngineService - Neo4j 기반 Edge Score 픽 엔진
#
# 백테스트 결과 (ML):
#   - Edge 85+: 100% (14/14)
#   - Edge 80-84: 80% (8/10)
#   - Edge 80+ 통합: 91.7% (22/24)
#
# 백테스트 결과 (Pickem Underdog):
#   - 0-0.5pt Away Underdog: 58.2% (2023-25 시즌)
#   - 0-1.5pt Away Underdog: 56.4%
#   - 플레이오프 Pickem: 71%
#
# 픽 타입:
#   - ML: Moneyline (승패)
#   - SPREAD: Against The Spread
#   - PICKEM: Pickem Underdog (특수 전략)
#   - TOTAL: Over/Under
#
# 사용법:
#   service = G9EngineService.new
#   picks = service.analyze_date('20260124')           # ML
#   picks = service.analyze_spread('20260124')         # Spread
#   picks = service.analyze_pickem('20260124')         # Pickem Underdog
#   picks = service.analyze_all('20260124')            # ML + Spread + Pickem + Total
#
class G9EngineService
  class EngineError < StandardError; end

  # Edge Score 임계값
  THRESHOLDS = {
    strong_bet: 85,
    bet: 80,
    caution: 70,
    lean: 60
  }.freeze

  # Spread 전용 임계값 (더 보수적)
  SPREAD_THRESHOLDS = {
    strong_bet: 80,
    bet: 75,
    caution: 65,
    lean: 55
  }.freeze

  # Total 전용 임계값
  TOTAL_THRESHOLDS = {
    strong_bet: 78,
    bet: 72,
    caution: 62,
    lean: 52
  }.freeze

  # Pickem Underdog 전략 설정
  # 백테스트: 0-0.5pt = 58.2%, 0-1.5pt = 56.4%
  PICKEM_CONFIG = {
    tight_spread: 0.5,      # 타이트 픽켐 (58.2% 승률)
    wide_spread: 1.5,       # 와이드 픽켐 (56.4% 승률)
    min_net_rtg_edge: 3.0,  # 최소 Net Rating 우위
    strong_net_rtg_edge: 8.0 # 강한 Net Rating 우위
  }.freeze

  # 위험 flow_state (Edge 65-80에서 37.5% 적중률)
  RISKY_FLOWS = %w[WARMING].freeze

  def initialize
    @client = Neo4jClient.new
  end

  # 특정 날짜의 경기 분석
  # @param date_str [String] 'YYYYMMDD' 형식
  # @return [Array<Hash>] 분석 결과 배열
  def analyze_date(date_str)
    result = @client.query(engine_query, { target_date: date_str })
    parse_results(result)
  rescue Neo4jClient::QueryError => e
    raise EngineError, "Neo4j query failed: #{e.message}"
  end

  # 오늘 경기 분석
  def analyze_today
    today = Date.current.strftime('%Y%m%d')
    analyze_date(today)
  end

  # === Spread Engine ===

  # Spread 분석 (ATS)
  # @param date_str [String] 'YYYYMMDD' 형식
  # @return [Array<Hash>] Spread 분석 결과
  def analyze_spread(date_str)
    result = @client.query(spread_engine_query, { target_date: date_str })
    parse_spread_results(result)
  rescue Neo4jClient::QueryError => e
    raise EngineError, "Spread query failed: #{e.message}"
  end

  # 오늘 Spread 분석
  def analyze_spread_today
    today = Date.current.strftime('%Y%m%d')
    analyze_spread(today)
  end

  # === Total Engine ===

  # Total 분석 (Over/Under)
  # @param date_str [String] 'YYYYMMDD' 형식
  # @return [Array<Hash>] Total 분석 결과
  def analyze_total(date_str)
    result = @client.query(total_engine_query, { target_date: date_str })
    parse_total_results(result)
  rescue Neo4jClient::QueryError => e
    raise EngineError, "Total query failed: #{e.message}"
  end

  # 오늘 Total 분석
  def analyze_total_today
    today = Date.current.strftime('%Y%m%d')
    analyze_total(today)
  end

  # === Pickem Underdog Engine ===

  # Pickem Underdog 분석 (0-1.5pt 어웨이 언더독)
  # 백테스트 결과: 58.2% (0-0.5pt), 56.4% (0-1.5pt)
  # @param date_str [String] 'YYYYMMDD' 형식
  # @return [Array<Hash>] Pickem 분석 결과
  def analyze_pickem(date_str)
    result = @client.query(pickem_engine_query, { target_date: date_str })
    parse_pickem_results(result)
  rescue Neo4jClient::QueryError => e
    raise EngineError, "Pickem query failed: #{e.message}"
  end

  # 오늘 Pickem 분석
  def analyze_pickem_today
    today = Date.current.strftime('%Y%m%d')
    analyze_pickem(today)
  end

  # 전체 분석 (ML + Spread + Pickem + Total)
  def analyze_all(date_str)
    {
      ml: analyze_date(date_str),
      spread: analyze_spread(date_str),
      pickem: analyze_pickem(date_str),
      total: analyze_total(date_str)
    }
  end

  # 분석 결과로 리포트 생성
  def generate_report(picks, date: Date.current)
    lines = []
    lines << header(date)
    lines << ""
    lines << summary_section(picks)
    lines << ""
    lines << picks_section(picks)
    lines << ""
    lines << footer
    lines.join("\n")
  end

  # 전체 파이프라인: 분석 + 리포트 생성 + 저장
  def run_daily(date: Date.current)
    date_str = date.strftime('%Y%m%d')
    picks = analyze_date(date_str)
    report = generate_report(picks, date: date)

    # 파일 저장
    report_dir = Rails.root.join('tmp', 'reports', 'g9')
    FileUtils.mkdir_p(report_dir)
    report_path = report_dir.join("#{date.strftime('%Y-%m-%d')}.md")
    File.write(report_path, report)

    { picks: picks, report: report, path: report_path }
  end

  private

  # === Total Engine Query ===

  # Total Engine v3.0 - 단순화
  # 복잡한 가중치 계산 대신 토탈 라인 구간별 분석
  # VPS 복구 후 백테스트로 검증 필요
  #
  # 가설 (검증 필요):
  #   Low (210-220): Under 편향 가능
  #   Medium (220-235): 중립
  #   High (235+): Over 편향 가능 (고득점 시대)
  def total_engine_query
    <<~CYPHER
      WITH $target_date AS target_date

      MATCH (g:Game)
      WHERE g.date = target_date
        AND g.status <> 'Final'
        AND g.total IS NOT NULL
      MATCH (home:Team {abbr: g.home_team})
      MATCH (away:Team {abbr: g.away_team})

      WITH g, home, away,
           g.total AS total_line,
           coalesce(home.off_rtg, 114) AS h_off,
           coalesce(away.off_rtg, 114) AS a_off,
           coalesce(home.def_rtg, 114) AS h_def,
           coalesce(away.def_rtg, 114) AS a_def

      // 토탈 라인 구간 분류
      WITH g, home, away, total_line, h_off, a_off, h_def, a_def,
           // 예상 토탈 (공격력 합 - 간단 공식)
           h_off + a_off AS expected_raw,
           CASE
             WHEN total_line < 220 THEN 'LOW'
             WHEN total_line < 235 THEN 'MEDIUM'
             ELSE 'HIGH'
           END AS total_tier

      // 예상 vs 마켓 비교
      WITH g, home, away, total_line, h_off, a_off, h_def, a_def,
           expected_raw, total_tier,
           expected_raw - total_line AS diff,
           CASE
             WHEN expected_raw - total_line > 5 THEN 'OVER'
             WHEN expected_raw - total_line < -5 THEN 'UNDER'
             ELSE 'NEUTRAL'
           END AS pick_direction,
           // 신호 강도 (diff 기반)
           CASE
             WHEN ABS(expected_raw - total_line) > 8 THEN 'LEAN'
             ELSE 'WATCH'
           END AS signal

      RETURN
        g.date AS date,
        away.abbr AS away,
        home.abbr AS home,
        round(total_line, 1) AS total_line,
        total_tier,
        round(expected_raw, 1) AS expected_total,
        round(diff, 1) AS diff,
        pick_direction,
        signal,
        round(h_off, 1) AS home_off_rtg,
        round(a_off, 1) AS away_off_rtg,
        round(h_def, 1) AS home_def_rtg,
        round(a_def, 1) AS away_def_rtg,
        g.time_et AS time_et,
        g.status AS status,
        g.home_score AS home_score,
        g.away_score AS away_score
      ORDER BY
        CASE signal WHEN 'LEAN' THEN 1 ELSE 2 END,
        ABS(diff) DESC
    CYPHER
  end

  # Total 결과 파싱 v3.0
  def parse_total_results(raw_results)
    raw_results.map do |r|
      signal_raw = r['signal']
      pick_dir = r['pick_direction']
      signal = determine_total_signal_v3(signal_raw, pick_dir, r['diff'].to_f)

      {
        date: r['date'],
        matchup: "#{r['away']} @ #{r['home']}",
        away: r['away'],
        home: r['home'],
        pick_type: 'TOTAL',
        total_line: r['total_line'].to_f,
        total_tier: r['total_tier'],
        expected_total: r['expected_total'].to_f,
        diff: r['diff'].to_f,
        pick_direction: pick_dir,
        home_off_rtg: r['home_off_rtg'].to_f,
        away_off_rtg: r['away_off_rtg'].to_f,
        home_def_rtg: r['home_def_rtg'].to_f,
        away_def_rtg: r['away_def_rtg'].to_f,
        time_et: r['time_et'],
        status: r['status'],
        home_score: r['home_score'],
        away_score: r['away_score'],
        signal: signal,
        actionable: signal_raw == 'LEAN' && pick_dir != 'NEUTRAL'
      }
    end
  end

  # Total Signal 결정 v3.0
  # signal_raw: LEAN, WATCH
  # pick_dir: OVER, UNDER, NEUTRAL
  def determine_total_signal_v3(signal_raw, pick_dir, diff)
    return '🚫 TOTAL NEUTRAL' if pick_dir == 'NEUTRAL'

    prefix = pick_dir == 'OVER' ? '📈' : '📉'
    diff_label = "(#{diff > 0 ? '+' : ''}#{diff.round(1)})"

    case signal_raw
    when 'LEAN'
      "#{prefix} #{pick_dir} LEAN #{diff_label}"
    else
      "➖ #{pick_dir} WATCH #{diff_label}"
    end
  end

  # 기존 함수 유지 (호환성)
  def determine_total_signal(edge, side)
    prefix = side == 'OVER' ? '📈' : '📉'

    case edge
    when TOTAL_THRESHOLDS[:strong_bet]..Float::INFINITY
      "#{prefix} STRONG #{side}"
    when TOTAL_THRESHOLDS[:bet]...TOTAL_THRESHOLDS[:strong_bet]
      "#{prefix} #{side} BET"
    when TOTAL_THRESHOLDS[:caution]...TOTAL_THRESHOLDS[:bet]
      "#{prefix} #{side} LEAN"
    when TOTAL_THRESHOLDS[:lean]...TOTAL_THRESHOLDS[:caution]
      "➖ #{side} WATCH"
    else
      '🚫 TOTAL PASS'
    end
  end

  # === Pickem Underdog Engine Query ===

  # Pickem Underdog 쿼리
  # 조건: 스프레드 -1.5 ~ 0 (홈 1.5점 이내 페이보릿) + 어웨이팀 Net Rating 우위
  # 백테스트 결과:
  #   - TIGHT (0-0.5pt): 70.0% (21/30)
  #   - WIDE (1.0-1.5pt): 59.6% (34/57)
  #   - 전체: 63.2% (55/87)
  def pickem_engine_query
    <<~CYPHER
      WITH $target_date AS target_date

      // 1. Pickem 경기 필터 (홈이 1.5점 이내 페이보릿)
      // 스프레드 규칙: 음수 = 홈 페이보릿 (예: -1.5 = 홈이 1.5점 유리)
      MATCH (g:Game)
      WHERE g.date = target_date
        AND g.spread IS NOT NULL
        AND g.spread >= -1.5 AND g.spread <= 0

      // 2. 팀 매칭
      MATCH (home:Team {abbr: g.home_team})
      MATCH (away:Team {abbr: g.away_team})

      // 3. Net Rating 비교
      WITH g, home, away,
           coalesce(away.net_rtg, 0) AS a_net,
           coalesce(home.net_rtg, 0) AS h_net,
           coalesce(away.win_pct, 0.5) AS a_pct,
           coalesce(home.win_pct, 0.5) AS h_pct

      // 4. 어웨이팀이 Net Rating 우위인 경우만 (핵심 조건)
      WHERE a_net > h_net

      // 5. Pickem Edge Score 계산
      // 어웨이 언더독 스프레드 = -spread (예: spread=-1.5 → 어웨이 +1.5)
      WITH g, home, away, a_net, h_net, a_pct, h_pct,
           a_net - h_net AS net_rtg_edge,
           -g.spread AS away_spread,  // 어웨이 관점 스프레드
           // 기본 점수 60 (조건 충족 시)
           60 +
           // Net Rating 우위 보너스 (백테스트: 5-8pt = 66.7%)
           CASE
             WHEN a_net - h_net >= 8 THEN 15   // 강한 우위
             WHEN a_net - h_net >= 5 THEN 20   // 최적 구간 (66.7%)
             WHEN a_net - h_net >= 3 THEN 10   // 중간 우위
             ELSE 15                            // 약한 우위도 64.1%
           END +
           // 타이트 스프레드 보너스 (백테스트: TIGHT = 70%)
           CASE
             WHEN g.spread >= -0.5 THEN 15     // TIGHT (70%)
             WHEN g.spread >= -1.0 THEN 5      // MEDIUM
             ELSE 0                             // WIDE (59.6%)
           END +
           // 승률 우위 보너스
           CASE
             WHEN a_pct - h_pct >= 0.15 THEN 5  // 15%+ 승률 우위
             WHEN a_pct - h_pct >= 0.10 THEN 3  // 10%+ 승률 우위
             ELSE 0
           END
           AS pickem_edge

      RETURN
        g.date AS date,
        g.date_et AS date_et,
        g.time_et AS time_et,
        away.abbr AS away,
        home.abbr AS home,
        -g.spread AS spread,  // 어웨이 관점으로 변환 (+1.5 형태)
        round(pickem_edge, 1) AS pickem_edge_score,
        away.abbr AS recommended,
        'AWAY' AS pick_side,
        round(a_net, 1) AS away_net_rtg,
        round(h_net, 1) AS home_net_rtg,
        round(net_rtg_edge, 1) AS net_rtg_edge,
        round(a_pct * 100) AS away_win_pct,
        round(h_pct * 100) AS home_win_pct,
        g.total AS total_line,
        g.status AS status,
        g.home_score AS home_score,
        g.away_score AS away_score,
        g.spread_result AS actual_result,
        CASE
          WHEN g.spread >= -0.5 THEN 'TIGHT'   // 70% 커버율
          WHEN g.spread >= -1.0 THEN 'MEDIUM'
          ELSE 'WIDE'                           // 59.6% 커버율
        END AS pickem_type
      ORDER BY pickem_edge DESC
    CYPHER
  end

  # Pickem 결과 파싱
  def parse_pickem_results(raw_results)
    raw_results.map do |r|
      edge = r['pickem_edge_score'].to_f
      signal = determine_pickem_signal(edge, r['pickem_type'])

      {
        date: r['date'],
        date_et: r['date_et'],
        time_et: r['time_et'],
        matchup: "#{r['away']} @ #{r['home']}",
        away: r['away'],
        home: r['home'],
        pick_type: 'PICKEM',
        spread: r['spread'].to_f,
        pickem_edge_score: edge,
        recommended: r['recommended'],
        pick_side: r['pick_side'],
        away_net_rtg: r['away_net_rtg'].to_f,
        home_net_rtg: r['home_net_rtg'].to_f,
        net_rtg_edge: r['net_rtg_edge'].to_f,
        away_win_pct: r['away_win_pct'].to_i,
        home_win_pct: r['home_win_pct'].to_i,
        total_line: r['total_line'],
        status: r['status'],
        home_score: r['home_score'],
        away_score: r['away_score'],
        actual_result: r['actual_result'],
        pickem_type: r['pickem_type'],
        signal: signal,
        actionable: edge >= 75  # Pickem은 75+ 액션
      }
    end
  end

  # Pickem Signal 결정
  def determine_pickem_signal(edge, pickem_type)
    type_emoji = case pickem_type
                 when 'TIGHT' then '🎯'  # 타이트 (58.2%)
                 when 'MEDIUM' then '📍' # 중간
                 else '📌'               # 와이드 (56.4%)
                 end

    case edge
    when 90..Float::INFINITY
      "#{type_emoji} ELITE PICKEM"
    when 85...90
      "#{type_emoji} STRONG PICKEM"
    when 80...85
      "#{type_emoji} PICKEM BET"
    when 75...80
      "#{type_emoji} PICKEM LEAN"
    when 70...75
      "➖ PICKEM WATCH"
    else
      '🚫 PICKEM PASS'
    end
  end

  # === Spread Engine Query ===

  # Spread Engine v3.0 - 백테스트 기반 단순화
  # 핵심: 5-15pt 스프레드에서 언더독 62% 커버
  # 복잡한 가중치 계산 대신 역사적 데이터 기반 규칙
  #
  # 백테스트 결과 (2024-10 ~ 2026-01, 2247 경기):
  #   0-2pt:  48.6% underdog cover (엣지 없음)
  #   2-5pt:  54.8% underdog cover (+4.8% 엣지)
  #   5-10pt: 62.0% underdog cover (+12% 엣지)
  #   10-15pt:62.5% underdog cover (+12.5% 엣지)
  #   15+pt:  55.8% underdog cover (+5.8% 엣지)
  def spread_engine_query
    <<~CYPHER
      WITH $target_date AS target_date

      MATCH (g:Game)
      WHERE g.date = target_date
        AND g.status <> 'Final'
        AND g.spread IS NOT NULL
      MATCH (home:Team {abbr: g.home_team})
      MATCH (away:Team {abbr: g.away_team})

      WITH g, home, away,
           g.spread AS spread,
           ABS(g.spread) AS abs_spread,
           // 언더독 판별: spread < 0 = away favored = home is underdog
           CASE WHEN g.spread < 0 THEN home.abbr ELSE away.abbr END AS underdog,
           CASE WHEN g.spread < 0 THEN 'HOME' ELSE 'AWAY' END AS dog_side,
           CASE WHEN g.spread < 0 THEN away.abbr ELSE home.abbr END AS favorite,
           CASE WHEN g.spread < 0 THEN 'AWAY' ELSE 'HOME' END AS fav_side

      // 스프레드 구간별 분류 및 역사적 커버율
      WITH g, home, away, spread, abs_spread, underdog, dog_side, favorite, fav_side,
           CASE
             WHEN abs_spread >= 15 THEN '15+'
             WHEN abs_spread >= 10 THEN '10-15'
             WHEN abs_spread >= 5 THEN '5-10'
             WHEN abs_spread >= 2 THEN '2-5'
             ELSE '0-2'
           END AS spread_tier,
           CASE
             WHEN abs_spread >= 10 AND abs_spread < 15 THEN 62.5
             WHEN abs_spread >= 5 AND abs_spread < 10 THEN 62.0
             WHEN abs_spread >= 15 THEN 55.8
             WHEN abs_spread >= 2 AND abs_spread < 5 THEN 54.8
             ELSE 48.6
           END AS historical_cover_pct,
           CASE
             WHEN abs_spread >= 5 AND abs_spread < 15 THEN 'RECOMMEND'
             WHEN abs_spread >= 2 AND abs_spread < 5 THEN 'LEAN'
             WHEN abs_spread >= 15 THEN 'NEUTRAL'
             ELSE 'PASS'
           END AS signal

      RETURN
        g.date AS date,
        away.abbr AS away,
        home.abbr AS home,
        round(spread, 1) AS spread,
        round(abs_spread, 1) AS abs_spread,
        spread_tier,
        underdog AS recommended,
        dog_side AS pick_side,
        favorite,
        fav_side,
        historical_cover_pct,
        signal,
        g.time_et AS time_et,
        g.status AS status,
        g.home_score AS home_score,
        g.away_score AS away_score
      ORDER BY
        CASE signal
          WHEN 'RECOMMEND' THEN 1
          WHEN 'LEAN' THEN 2
          WHEN 'NEUTRAL' THEN 3
          ELSE 4
        END,
        abs_spread DESC
    CYPHER
  end

  # Spread 결과 파싱 v3.0
  # 백테스트 기반 단순화 - 역사적 커버율과 신호로 판단
  def parse_spread_results(raw_results)
    raw_results.map do |r|
      signal_raw = r['signal']
      historical_pct = r['historical_cover_pct'].to_f
      signal = determine_spread_signal_v3(signal_raw, historical_pct)

      {
        date: r['date'],
        matchup: "#{r['away']} @ #{r['home']}",
        away: r['away'],
        home: r['home'],
        pick_type: 'SPREAD',
        spread: r['spread'].to_f,
        abs_spread: r['abs_spread'].to_f,
        spread_tier: r['spread_tier'],
        recommended: r['recommended'],  # 언더독
        pick_side: r['pick_side'],       # HOME or AWAY
        favorite: r['favorite'],
        fav_side: r['fav_side'],
        historical_cover_pct: historical_pct,
        time_et: r['time_et'],
        status: r['status'],
        home_score: r['home_score'],
        away_score: r['away_score'],
        signal: signal,
        actionable: %w[RECOMMEND LEAN].include?(signal_raw)
      }
    end
  end

  # Spread Signal 결정 v3.0
  # 백테스트 기반 - 역사적 커버율로 신호 결정
  # signal_raw: RECOMMEND, LEAN, NEUTRAL, PASS
  # historical_pct: 해당 구간 역사적 언더독 커버율
  def determine_spread_signal_v3(signal_raw, historical_pct)
    pct_label = "(#{historical_pct.round(1)}%)"

    case signal_raw
    when 'RECOMMEND'
      "💎 DOG COVER #{pct_label}"  # 5-15pt, 62% edge
    when 'LEAN'
      "📍 DOG LEAN #{pct_label}"   # 2-5pt, 54.8% edge
    when 'NEUTRAL'
      "➖ BIG SPREAD #{pct_label}" # 15+pt, 55.8% but risky
    else
      "🚫 COIN FLIP #{pct_label}"  # 0-2pt, 48.6%
    end
  end

  # 기존 함수 유지 (호환성)
  def determine_spread_signal(edge, cover_value = 0)
    value_label = if cover_value.abs >= 5
                    " (#{cover_value > 0 ? '+' : ''}#{cover_value.round(1)}pt)"
                  else
                    ""
                  end

    case edge
    when SPREAD_THRESHOLDS[:strong_bet]..Float::INFINITY
      "💎 STRONG SPREAD#{value_label}"
    when SPREAD_THRESHOLDS[:bet]...SPREAD_THRESHOLDS[:strong_bet]
      "💎 SPREAD BET#{value_label}"
    when SPREAD_THRESHOLDS[:caution]...SPREAD_THRESHOLDS[:bet]
      '⚠️ SPREAD LEAN'
    when SPREAD_THRESHOLDS[:lean]...SPREAD_THRESHOLDS[:caution]
      '➖ SPREAD WATCH'
    else
      '🚫 SPREAD PASS'
    end
  end

  # === ML Engine Query (역배 알림 모드) ===

  # ML Engine v3.0 - 역배(Upset) 알림 전용
  # 핵심: 큰 스프레드 경기에서 페이보릿 추천하면 ROI 없음
  # 대신 역배 가능성 감지하여 경고
  #
  # 역배 조건:
  #   1. 페이보릿이 슬럼프 (COLD_STREAK, SLUMP, WARMING)
  #   2. 언더독이 핫스트릭 (HOT_STREAK, STRONG_UP)
  #   3. 스프레드 7pt 이상 (역배 의미 있는 범위)
  def engine_query
    <<~CYPHER
      WITH $target_date AS target_date

      MATCH (g:Game)
      WHERE g.date = target_date
        AND g.status <> 'Final'
        AND g.spread IS NOT NULL
        AND ABS(g.spread) >= 5  // 의미있는 스프레드만
      MATCH (home:Team {abbr: g.home_team})
      MATCH (away:Team {abbr: g.away_team})

      // TeamRegime 조인
      OPTIONAL MATCH (hr:TeamRegime) WHERE hr.team CONTAINS home.name
      OPTIONAL MATCH (ar:TeamRegime) WHERE ar.team CONTAINS away.name

      WITH g, home, away,
           g.spread AS spread,
           ABS(g.spread) AS abs_spread,
           // 페이보릿/언더독 판별
           CASE WHEN g.spread < 0 THEN home.abbr ELSE away.abbr END AS underdog,
           CASE WHEN g.spread < 0 THEN away.abbr ELSE home.abbr END AS favorite,
           CASE WHEN g.spread < 0 THEN 'HOME' ELSE 'AWAY' END AS dog_side,
           CASE WHEN g.spread < 0 THEN 'AWAY' ELSE 'HOME' END AS fav_side,
           // Flow states
           coalesce(hr.flow_state, 'NEUTRAL') AS h_flow,
           coalesce(ar.flow_state, 'NEUTRAL') AS a_flow,
           // Net ratings
           coalesce(home.net_rtg, 0) AS h_net,
           coalesce(away.net_rtg, 0) AS a_net

      // 역배 조건 체크
      WITH g, home, away, spread, abs_spread, underdog, favorite, dog_side, fav_side,
           h_flow, a_flow, h_net, a_net,
           // 페이보릿 flow (fav_side 기준)
           CASE WHEN fav_side = 'HOME' THEN h_flow ELSE a_flow END AS fav_flow,
           // 언더독 flow
           CASE WHEN dog_side = 'HOME' THEN h_flow ELSE a_flow END AS dog_flow,
           // Net rating 차이
           CASE WHEN fav_side = 'HOME' THEN h_net - a_net ELSE a_net - h_net END AS fav_net_edge

      // 역배 경고 조건
      WITH g, home, away, spread, abs_spread, underdog, favorite, dog_side, fav_side,
           fav_flow, dog_flow, fav_net_edge, h_net, a_net,
           // 페이보릿 슬럼프?
           CASE WHEN fav_flow IN ['COLD_STREAK', 'SLUMP', 'WARMING'] THEN true ELSE false END AS fav_slump,
           // 언더독 핫스트릭?
           CASE WHEN dog_flow IN ['HOT_STREAK', 'STRONG_UP'] THEN true ELSE false END AS dog_hot,
           // 스프레드 대비 실제 실력차 괴리
           // fav_net_edge가 스프레드보다 작으면 over-valued
           CASE WHEN fav_net_edge < abs_spread * 0.7 THEN true ELSE false END AS line_inflated

      // 최종 역배 신호
      WITH g, home, away, spread, abs_spread, underdog, favorite, dog_side, fav_side,
           fav_flow, dog_flow, fav_net_edge, fav_slump, dog_hot, line_inflated, h_net, a_net,
           // 역배 알림 조건 (하나라도 만족)
           CASE
             WHEN fav_slump AND dog_hot THEN 'HIGH'     // 둘 다 만족 = 강한 역배 경고
             WHEN fav_slump AND abs_spread >= 10 THEN 'MEDIUM'  // 페이보릿 슬럼프 + 큰 스프레드
             WHEN dog_hot AND abs_spread >= 10 THEN 'MEDIUM'    // 언더독 핫 + 큰 스프레드
             WHEN line_inflated AND abs_spread >= 12 THEN 'LOW' // 라인 과대평가
             ELSE 'NONE'
           END AS upset_alert

      // NONE 제외 (역배 경고 있는 경기만)
      WHERE upset_alert <> 'NONE'

      RETURN
        g.date AS date,
        away.abbr AS away,
        home.abbr AS home,
        round(spread, 1) AS spread,
        round(abs_spread, 1) AS abs_spread,
        favorite,
        fav_side,
        underdog,
        dog_side,
        fav_flow,
        dog_flow,
        round(fav_net_edge, 1) AS fav_net_edge,
        fav_slump,
        dog_hot,
        line_inflated,
        upset_alert,
        round(h_net, 1) AS home_net_rtg,
        round(a_net, 1) AS away_net_rtg,
        g.time_et AS time_et,
        g.status AS status,
        g.home_score AS home_score,
        g.away_score AS away_score
      ORDER BY
        CASE upset_alert
          WHEN 'HIGH' THEN 1
          WHEN 'MEDIUM' THEN 2
          ELSE 3
        END,
        abs_spread DESC
    CYPHER
  end

  # 쿼리 결과 파싱 v3.0 - 역배 알림 모드
  def parse_results(raw_results)
    raw_results.map do |r|
      upset_alert = r['upset_alert']
      signal = determine_upset_signal(upset_alert, r['fav_slump'], r['dog_hot'])

      {
        date: r['date'],
        matchup: "#{r['away']} @ #{r['home']}",
        away: r['away'],
        home: r['home'],
        spread: r['spread'].to_f,
        abs_spread: r['abs_spread'].to_f,
        favorite: r['favorite'],
        fav_side: r['fav_side'],
        underdog: r['underdog'],
        dog_side: r['dog_side'],
        fav_flow: r['fav_flow'],
        dog_flow: r['dog_flow'],
        fav_net_edge: r['fav_net_edge'].to_f,
        fav_slump: r['fav_slump'],
        dog_hot: r['dog_hot'],
        line_inflated: r['line_inflated'],
        upset_alert: upset_alert,
        signal: signal,
        home_net_rtg: r['home_net_rtg'].to_f,
        away_net_rtg: r['away_net_rtg'].to_f,
        time_et: r['time_et'],
        status: r['status'],
        home_score: r['home_score'],
        away_score: r['away_score'],
        actionable: %w[HIGH MEDIUM].include?(upset_alert)
      }
    end
  end

  # 역배 경고 Signal 결정 v3.0
  def determine_upset_signal(upset_alert, fav_slump, dog_hot)
    details = []
    details << '페이보릿슬럼프' if fav_slump
    details << '언더독핫' if dog_hot
    detail_str = details.any? ? " (#{details.join('+')})" : ''

    case upset_alert
    when 'HIGH'
      "🚨 역배경고#{detail_str}"
    when 'MEDIUM'
      "⚠️ 역배주의#{detail_str}"
    when 'LOW'
      "📊 역배관찰#{detail_str}"
    else
      '✅ 정상'
    end
  end

  # 기존 함수 유지 (호환성)
  def determine_signal(edge, risky)
    return '🚨 RISKY' if risky && edge >= 65 && edge < 80

    case edge
    when THRESHOLDS[:strong_bet]..Float::INFINITY
      '💎 STRONG BET'
    when THRESHOLDS[:bet]...THRESHOLDS[:strong_bet]
      '💎 BET'
    when THRESHOLDS[:caution]...THRESHOLDS[:bet]
      '⚠️ CAUTION'
    when THRESHOLDS[:lean]...THRESHOLDS[:caution]
      '➖ LEAN'
    else
      '🚫 PASS'
    end
  end

  # 리포트 헤더
  def header(date)
    <<~HEADER.strip
      ======================================================================
      🏀 G9 Engine v2.3 - Daily Analysis Report
      📅 #{date.strftime('%Y-%m-%d')} (KST)
      ======================================================================

      ## 📊 백테스트 검증 성과
      | 티어 | Edge 범위 | 적중률 | Action |
      |------|-----------|--------|--------|
      | 💎 STRONG | 85+ | 100% | 강승부 |
      | 💎 BET | 80-84 | 80% | 베팅 |
      | ⚠️ CAUTION | 70-79 | 61% | 주의 |
      | ➖ LEAN | 60-69 | 68% | 관망 |
      | 🚫 PASS | <60 | 54% | 패스 |
    HEADER
  end

  # 요약 섹션
  def summary_section(picks)
    actionable = picks.select { |p| p[:actionable] }
    strong = picks.count { |p| p[:edge_score] >= THRESHOLDS[:strong_bet] && !p[:risky] }
    bet = picks.count { |p| p[:edge_score] >= THRESHOLDS[:bet] && p[:edge_score] < THRESHOLDS[:strong_bet] && !p[:risky] }
    risky = picks.count { |p| p[:risky] }

    lines = []
    lines << "## 🎯 오늘의 요약"
    lines << ""
    lines << "- 총 경기: #{picks.count}개"
    lines << "- 💎 STRONG BET (85+): #{strong}개"
    lines << "- 💎 BET (80-84): #{bet}개"
    lines << "- 🚨 RISKY (WARMING): #{risky}개"
    lines << ""

    if actionable.any?
      lines << "### 🏆 액션 가능 픽 (Edge 80+)"
      lines << ""
      actionable.each do |p|
        lines << "- **#{p[:matchup]}**: #{p[:recommended]} (Edge #{p[:edge_score]}) #{p[:signal]}"
      end
    else
      lines << "### ⚠️ 오늘은 Edge 80+ 경기 없음 - PASS 권장"
    end

    lines.join("\n")
  end

  # 경기별 분석 섹션
  def picks_section(picks)
    lines = []
    lines << "## 🏀 경기별 분석"
    lines << ""

    picks.each do |p|
      lines << "----------------------------------------------------------------------"
      lines << "### #{p[:matchup]}"
      lines << ""
      lines << "| 항목 | 값 |"
      lines << "|------|-----|"
      lines << "| Edge Score | **#{p[:edge_score]}** |"
      lines << "| 추천 | #{p[:recommended]} (#{p[:side]}) |"
      lines << "| Signal | #{p[:signal]} |"
      lines << "| Flow State | #{p[:flow]} |"
      lines << "| Home Win% | #{p[:home_win_pct]}% |"
      lines << "| Away Win% | #{p[:away_win_pct]}% |"
      lines << "| Home Net RTG | #{p[:home_net_rtg]} |"
      lines << "| Away Net RTG | #{p[:away_net_rtg]} |"

      if p[:status] == 'Final' && p[:home_score] && p[:away_score]
        winner = p[:home_score] > p[:away_score] ? p[:home] : p[:away]
        result = p[:recommended] == winner ? '✅ HIT' : '❌ MISS'
        lines << "| 결과 | #{p[:home_score]}-#{p[:away_score]} → #{result} |"
      end

      lines << ""

      # Action 가이드
      if p[:actionable]
        lines << "**🏆 ACTION: #{p[:recommended]} 베팅 권장**"
      elsif p[:risky]
        lines << "**⚠️ RISKY: WARMING 상태 - 베팅 회피 권장**"
      elsif p[:edge_score] >= THRESHOLDS[:caution]
        lines << "**⚠️ CAUTION: 관망 권장**"
      else
        lines << "**🚫 PASS: Edge 부족**"
      end
      lines << ""
    end

    lines.join("\n")
  end

  # 푸터
  def footer
    <<~FOOTER.strip
      ======================================================================
      ⚠️ G9 Engine v2.3 - 백테스트 기반 분석 시스템
      📊 데이터: Neo4j (Team Stats, TeamRegime, Game)
      🎯 철학: "We sell Certainty, not Lottery."
      ======================================================================
    FOOTER
  end
end
