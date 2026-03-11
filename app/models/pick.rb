# frozen_string_literal: true

# Pick - G9 Engine 자동 생성 픽
#
# 상품화 핵심 테이블:
# - 엔진이 생성한 모든 픽 추적
# - 결과 기반 성과 분석
# - 타입별/시그널별 ROI 계산
#
class Pick < ApplicationRecord
  belongs_to :game

  # 픽 타입
  PICK_TYPES = %w[ML SPREAD TOTAL].freeze

  # 픽 사이드
  PICK_SIDES = {
    'ML' => %w[HOME AWAY],
    'SPREAD' => %w[HOME AWAY],
    'TOTAL' => %w[OVER UNDER]
  }.freeze

  # 시그널
  SIGNALS = %w[STRONG_BET BET CAUTION LEAN PASS].freeze

  # 결과
  RESULTS = %w[win loss push pending void].freeze

  # Validations
  validates :pick_type, presence: true, inclusion: { in: PICK_TYPES }
  validates :pick_side, presence: true
  validates :edge_score, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :confidence, presence: true, inclusion: { in: 1..5 }
  validates :signal, presence: true, inclusion: { in: SIGNALS }
  validates :result, inclusion: { in: RESULTS }, allow_nil: true
  validates :units, numericality: { greater_than: 0 }, allow_nil: true

  validate :pick_side_matches_type

  # Scopes
  scope :published, -> { where(status: 'published') }
  scope :pending, -> { where(result: 'pending') }
  scope :graded, -> { where(result: %w[win loss push]) }
  scope :actionable, -> { where(signal: %w[STRONG_BET BET]) }

  scope :by_type, ->(type) { where(pick_type: type) }
  scope :by_signal, ->(signal) { where(signal: signal) }
  scope :wins, -> { where(result: 'win') }
  scope :losses, -> { where(result: 'loss') }

  scope :today, -> { joins(:game).where('DATE(games.game_date) = ?', Date.current) }
  scope :this_week, -> { joins(:game).where('games.game_date >= ?', 1.week.ago) }
  scope :this_month, -> { joins(:game).where('games.game_date >= ?', 1.month.ago) }

  # Callbacks
  before_save :calculate_profit, if: :result_changed?

  # === Class Methods ===

  # 타입별 성적
  def self.record_by_type(type = nil)
    scope = graded
    scope = scope.by_type(type) if type

    wins = scope.wins.count
    losses = scope.losses.count
    pushes = scope.where(result: 'push').count
    total = wins + losses

    {
      wins: wins,
      losses: losses,
      pushes: pushes,
      total: total,
      record: "#{wins}-#{losses}#{pushes > 0 ? "-#{pushes}" : ''}",
      win_pct: total > 0 ? (wins.to_f / total * 100).round(1) : 0,
      profit: scope.sum(:profit).round(2)
    }
  end

  # 시그널별 성적
  def self.record_by_signal(signal = nil)
    scope = graded
    scope = scope.by_signal(signal) if signal

    record_by_type.merge(signal: signal)
  end

  # Edge 구간별 성적
  def self.record_by_edge_tier
    tiers = {
      'STRONG_85+' => graded.where('edge_score >= 85'),
      'BET_80-84' => graded.where('edge_score >= 80 AND edge_score < 85'),
      'CAUTION_70-79' => graded.where('edge_score >= 70 AND edge_score < 80'),
      'LEAN_60-69' => graded.where('edge_score >= 60 AND edge_score < 70'),
      'PASS_<60' => graded.where('edge_score < 60')
    }

    tiers.transform_values do |scope|
      wins = scope.wins.count
      losses = scope.losses.count
      total = wins + losses
      {
        wins: wins,
        losses: losses,
        total: total,
        win_pct: total > 0 ? (wins.to_f / total * 100).round(1) : 0,
        profit: scope.sum(:profit).round(2)
      }
    end
  end

  # 전체 ROI
  def self.total_roi
    graded_picks = graded
    total_units = graded_picks.sum(:units)
    total_profit = graded_picks.sum(:profit)

    return 0 if total_units.zero?
    (total_profit / total_units * 100).round(2)
  end

  # 일별 성적 요약
  def self.daily_summary(date = Date.current)
    picks = joins(:game).where('DATE(games.game_date) = ?', date)

    {
      date: date,
      total: picks.count,
      actionable: picks.actionable.count,
      graded: picks.graded.count,
      wins: picks.wins.count,
      losses: picks.losses.count,
      profit: picks.sum(:profit).round(2)
    }
  end

  # === Instance Methods ===

  def actionable?
    signal.in?(%w[STRONG_BET BET])
  end

  def graded?
    result.in?(%w[win loss push])
  end

  def pending?
    result == 'pending' || result.nil?
  end

  # 결과 기록
  def record_result!(game_result)
    return if graded?

    self.result = calculate_result(game_result)
    self.result_recorded_at = Time.current
    save!
  end

  # 분석 데이터 접근 헬퍼
  def factors
    analysis_data&.dig('factors') || []
  end

  def pattern_matched
    analysis_data&.dig('pattern_matched')
  end

  private

  def pick_side_matches_type
    valid_sides = PICK_SIDES[pick_type]
    return if valid_sides&.include?(pick_side)

    errors.add(:pick_side, "#{pick_side} is not valid for #{pick_type}")
  end

  def calculate_profit
    return unless result.in?(%w[win loss push])

    case result
    when 'win'
      # 표준 -110 주스 가정: 1u 베팅 → 0.91u 수익
      self.profit = (units || 1.0) * 0.91
    when 'loss'
      self.profit = -(units || 1.0)
    when 'push'
      self.profit = 0
    end
  end

  def calculate_result(game_result)
    case pick_type
    when 'ML'
      calculate_ml_result(game_result)
    when 'SPREAD'
      calculate_spread_result(game_result)
    when 'TOTAL'
      calculate_total_result(game_result)
    end
  end

  def calculate_ml_result(game_result)
    winner = game_result.home_score > game_result.away_score ? 'HOME' : 'AWAY'
    pick_side == winner ? 'win' : 'loss'
  end

  def calculate_spread_result(game_result)
    return 'pending' unless game_result.spread_result.present?

    case game_result.spread_result
    when 'home_covered'
      pick_side == 'HOME' ? 'win' : 'loss'
    when 'away_covered'
      pick_side == 'AWAY' ? 'win' : 'loss'
    when 'push'
      'push'
    end
  end

  def calculate_total_result(game_result)
    return 'pending' unless game_result.total_result.present?

    case game_result.total_result
    when 'over'
      pick_side == 'OVER' ? 'win' : 'loss'
    when 'under'
      pick_side == 'UNDER' ? 'win' : 'loss'
    when 'push'
      'push'
    end
  end
end
