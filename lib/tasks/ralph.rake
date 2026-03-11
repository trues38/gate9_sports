# frozen_string_literal: true

# RALPH v2.0 - Recursive Autonomous Learning & Prediction Helper
#
# 시그널/트리거 기반 자체검증 시스템
#
# 주간 사이클:
# 1. 경기 결과 기록 (ralph:record)
# 2. 트리거별 승률 분석 (ralph:trigger_stats)
# 3. 시그널별 검증 (ralph:signal_stats)
# 4. 신뢰도 캘리브레이션 (ralph:calibration)
# 5. 피드백 출력 (ralph:feedback)
#
# 실행: 매주 월요일 또는 수동
#
namespace :ralph do
  desc 'RALPH v2.0 전체 사이클 (결과기록 → 분석 → 피드백)'
  task cycle: :environment do
    puts "=" * 60
    puts "🤖 RALPH v2.0 - Weekly Cycle"
    puts "   Started: #{Time.current.in_time_zone('Asia/Seoul').strftime('%Y-%m-%d %H:%M KST')}"
    puts "=" * 60

    Rake::Task['ralph:record'].invoke
    Rake::Task['ralph:trigger_stats'].invoke
    Rake::Task['ralph:signal_stats'].invoke
    Rake::Task['ralph:calibration'].invoke
    Rake::Task['ralph:feedback'].invoke

    puts "\n✅ RALPH v2.0 cycle completed!"
  end

  desc '경기 결과 자동 기록'
  task record: :environment do
    puts "\n📊 Step 1: Recording game results..."

    # 결과 미기록 + 경기 종료된 보고서 찾기
    pending_reports = Report.joins(:game)
                            .where(result: [nil, 'pending'])
                            .where('games.game_date < ?', Time.current - 3.hours)

    recorded = 0
    pending_reports.find_each do |report|
      game = report.game

      # 스코어가 있으면 결과 계산
      if game.home_score.present? && game.away_score.present?
        result = report.calculate_result_from_scores(game.home_score, game.away_score)

        if result
          report.record_result!(result,
            home_score: game.home_score,
            away_score: game.away_score
          )
          recorded += 1
          print result == 'win' ? '✓' : (result == 'loss' ? '✗' : '—')
        end
      end
    end

    puts "\n   ✓ Recorded #{recorded} results"
  end

  desc '트리거별 승률 분석 (8주 롤링)'
  task trigger_stats: :environment do
    puts "\n📈 Step 2: Trigger Performance Analysis..."

    start_date = 8.weeks.ago.to_date
    reports = Report.with_result
                    .where('published_at >= ?', start_date)
                    .where.not(structured_data: [nil, ''])

    trigger_stats = Hash.new { |h, k| h[k] = { wins: 0, losses: 0, pushes: 0 } }

    reports.find_each do |r|
      data = parse_structured_data(r.structured_data)
      next unless data

      triggers = data['triggers'] || []
      triggers.each do |trigger|
        case r.result
        when 'win' then trigger_stats[trigger][:wins] += 1
        when 'loss' then trigger_stats[trigger][:losses] += 1
        when 'push' then trigger_stats[trigger][:pushes] += 1
        end
      end
    end

    puts "\n   Trigger Performance (#{start_date} ~ today):"
    puts "   " + "-" * 55

    # 정렬: 승률 높은 순
    sorted = trigger_stats.sort_by do |_, v|
      total = v[:wins] + v[:losses]
      total > 0 ? -(v[:wins].to_f / total) : 0
    end

    sorted.each do |trigger, stats|
      total = stats[:wins] + stats[:losses]
      next if total < 3  # 최소 샘플

      win_rate = (stats[:wins].to_f / total * 100).round(1)
      emoji = win_rate >= 60 ? '🔥' : (win_rate >= 50 ? '✅' : '❌')
      bar = '█' * (win_rate / 5).to_i + '░' * (20 - (win_rate / 5).to_i)

      puts "   #{emoji} #{trigger.ljust(20)} #{stats[:wins]}/#{total} (#{win_rate}%) #{bar}"
    end

    @trigger_stats = trigger_stats
  end

  desc '백테스트 시그널별 검증'
  task signal_stats: :environment do
    puts "\n📊 Step 3: Signal Performance Validation..."

    start_date = 8.weeks.ago.to_date
    reports = Report.with_result
                    .where('published_at >= ?', start_date)
                    .where.not(structured_data: [nil, ''])

    signal_stats = Hash.new { |h, k| h[k] = { wins: 0, losses: 0, pushes: 0 } }

    reports.find_each do |r|
      data = parse_structured_data(r.structured_data)
      next unless data

      signals = data['signals'] || []
      signals.each do |signal|
        case r.result
        when 'win' then signal_stats[signal][:wins] += 1
        when 'loss' then signal_stats[signal][:losses] += 1
        when 'push' then signal_stats[signal][:pushes] += 1
        end
      end
    end

    puts "\n   Backtest Signal Validation:"
    puts "   " + "-" * 55

    # 백테스트 기준 승률과 비교
    backtest_benchmarks = {
      'HIGH_EDGE_ML' => 79.4,
      'MID_EDGE_ML' => 66.9,
      'HIGH_EDGE_LOW_RISK' => 78.4,
      'STRONG_UP_FLOW' => 54.4,
      'COLLAPSE_FADE' => 53.1,
      'HOME_BIG_DOG' => 52.9,
      'LOW_TOTAL_UNDER' => 58.2
    }

    sorted = signal_stats.sort_by do |_, v|
      total = v[:wins] + v[:losses]
      total > 0 ? -(v[:wins].to_f / total) : 0
    end

    sorted.each do |signal, stats|
      total = stats[:wins] + stats[:losses]
      next if total < 3

      actual_rate = (stats[:wins].to_f / total * 100).round(1)
      benchmark = backtest_benchmarks[signal]

      if benchmark
        diff = actual_rate - benchmark
        status = diff >= -5 ? '✅' : '⚠️'
        puts "   #{status} #{signal.ljust(20)} #{stats[:wins]}/#{total} (#{actual_rate}%) [기준: #{benchmark}%, #{diff >= 0 ? '+' : ''}#{diff.round(1)}%]"
      else
        emoji = actual_rate >= 55 ? '✅' : '❓'
        puts "   #{emoji} #{signal.ljust(20)} #{stats[:wins]}/#{total} (#{actual_rate}%) [기준 없음]"
      end
    end

    @signal_stats = signal_stats
  end

  desc '신뢰도 캘리브레이션'
  task calibration: :environment do
    puts "\n⭐ Step 4: Confidence Calibration..."

    start_date = 8.weeks.ago.to_date

    puts "\n   Expected vs Actual Win Rate:"
    puts "   " + "-" * 55

    # 신뢰도별 예상 승률 (1⭐=40%, 2⭐=50%, 3⭐=60%, 4⭐=70%, 5⭐=80%)
    expected_rates = { 1 => 40, 2 => 50, 3 => 60, 4 => 70, 5 => 80 }
    calibration_results = {}

    (1..5).each do |conf|
      reports = Report.where(confidence: conf)
                      .where('published_at >= ?', start_date)
                      .with_result

      total = reports.count
      next if total < 3

      wins = reports.wins.count
      actual_rate = (wins.to_f / total * 100).round(1)
      expected = expected_rates[conf]
      diff = actual_rate - expected

      stars = '⭐' * conf + '☆' * (5 - conf)
      status = diff.abs <= 10 ? '✅' : (diff < -10 ? '⚠️' : '🔥')

      puts "   #{status} #{stars} 예상 #{expected}% vs 실제 #{actual_rate}% (#{wins}/#{total}) [#{diff >= 0 ? '+' : ''}#{diff.round(0)}%]"

      calibration_results[conf] = {
        expected: expected,
        actual: actual_rate,
        diff: diff,
        sample: total
      }
    end

    @calibration_results = calibration_results
  end

  desc '피드백 및 권장사항 출력'
  task feedback: :environment do
    puts "\n💡 Step 5: Feedback & Recommendations..."
    puts "   " + "-" * 55

    recommendations = []

    # 트리거 피드백
    if @trigger_stats
      @trigger_stats.each do |trigger, stats|
        total = stats[:wins] + stats[:losses]
        next if total < 5

        win_rate = stats[:wins].to_f / total * 100

        if win_rate >= 65
          recommendations << "🔥 #{trigger}: 승률 #{win_rate.round(1)}% → 적극 활용, 신뢰도 +0.5⭐"
        elsif win_rate < 45
          recommendations << "⚠️ #{trigger}: 승률 #{win_rate.round(1)}% → 주의 필요, 신뢰도 -0.5⭐"
        end
      end
    end

    # 시그널 피드백
    if @signal_stats
      backtest_benchmarks = {
        'HIGH_EDGE_ML' => 79.4,
        'MID_EDGE_ML' => 66.9,
        'HIGH_EDGE_LOW_RISK' => 78.4
      }

      @signal_stats.each do |signal, stats|
        total = stats[:wins] + stats[:losses]
        next if total < 5

        actual_rate = stats[:wins].to_f / total * 100
        benchmark = backtest_benchmarks[signal]

        if benchmark && actual_rate < benchmark - 15
          recommendations << "❌ #{signal}: 실제 #{actual_rate.round(1)}% < 기준 #{benchmark}% → 시그널 재검토 필요"
        end
      end
    end

    # 캘리브레이션 피드백
    if @calibration_results
      @calibration_results.each do |conf, data|
        if data[:diff] < -15
          recommendations << "📉 #{conf}⭐ 과대평가: 실제 #{data[:actual]}% < 예상 #{data[:expected]}% → 기준 하향 검토"
        elsif data[:diff] > 15
          recommendations << "📈 #{conf}⭐ 과소평가: 실제 #{data[:actual]}% > 예상 #{data[:expected]}% → 기준 상향 검토"
        end
      end
    end

    if recommendations.any?
      puts "\n   📋 Next Report Recommendations:"
      recommendations.each { |r| puts "   #{r}" }
    else
      puts "\n   ✅ 현재 시스템 캘리브레이션 양호"
    end

    # 요약 저장 (JSON)
    save_feedback_summary(recommendations)
  end

  desc '현재 상태 요약'
  task status: :environment do
    puts "\n📋 RALPH v2.0 Status"
    puts "=" * 60

    # 최근 성과
    recent = Report.where('published_at >= ?', 2.weeks.ago).with_result
    total = recent.count
    wins = recent.wins.count

    if total > 0
      puts "\n   최근 2주 성과: #{wins}/#{total} (#{(wins.to_f / total * 100).round(1)}%)"
    end

    # 결과 미기록 보고서
    pending = Report.where(result: [nil, 'pending'])
                    .joins(:game)
                    .where('games.game_date < ?', Time.current - 3.hours)
                    .count

    puts "   결과 미기록: #{pending}개" if pending > 0

    # 최근 피드백
    feedback_file = Rails.root.join('tmp', 'ralph_feedback.json')
    if File.exist?(feedback_file)
      feedback = JSON.parse(File.read(feedback_file))
      puts "\n   최근 피드백 (#{feedback['generated_at']}):"
      feedback['recommendations']&.first(3)&.each { |r| puts "   #{r}" }
    end

    puts "=" * 60
  end

  private

  def parse_structured_data(data)
    return nil if data.blank?

    case data
    when String
      JSON.parse(data) rescue nil
    when Hash
      data
    else
      nil
    end
  end

  def save_feedback_summary(recommendations)
    feedback = {
      generated_at: Time.current.iso8601,
      recommendations: recommendations,
      trigger_stats: @trigger_stats&.transform_values { |v|
        total = v[:wins] + v[:losses]
        { wins: v[:wins], total: total, rate: total > 0 ? (v[:wins].to_f / total * 100).round(1) : 0 }
      },
      signal_stats: @signal_stats&.transform_values { |v|
        total = v[:wins] + v[:losses]
        { wins: v[:wins], total: total, rate: total > 0 ? (v[:wins].to_f / total * 100).round(1) : 0 }
      },
      calibration: @calibration_results
    }

    File.write(Rails.root.join('tmp', 'ralph_feedback.json'), JSON.pretty_generate(feedback))
    puts "\n   📁 Feedback saved to tmp/ralph_feedback.json"
  end
end
