class Report < ApplicationRecord
  belongs_to :game
  has_many :analyst_picks, dependent: :destroy

  validates :content, presence: true

  RESULTS = %w[pending win loss push].freeze
  PICK_TYPES = %w[spread total moneyline].freeze

  scope :published, -> { where(status: "published").order(published_at: :desc) }
  scope :draft, -> { where(status: "draft") }
  scope :recent, -> { order(created_at: :desc) }
  scope :free_reports, -> { where(free: true) }
  scope :premium_reports, -> { where(free: false) }

  # Result tracking scopes
  scope :with_result, -> { where.not(result: [nil, "pending"]) }
  scope :pending_result, -> { where(result: [nil, "pending"]) }
  scope :wins, -> { where(result: "win") }
  scope :losses, -> { where(result: "loss") }
  scope :pushes, -> { where(result: "push") }

  delegate :sport, to: :game

  # structured_data 표준 포맷:
  # {
  #   "triggers": ["B2B", "3in4", "TeamRegime_weakness"],
  #   "signals": ["HIGH_EDGE_ML", "STRONG_UP_FLOW"],
  #   "edge_score": 72,
  #   "away_regime": "WARMING",
  #   "home_regime": "COOLING",
  #   "notes": "추가 메모"
  # }
  STANDARD_TRIGGERS = %w[
    B2B 3in4 4in5
    TeamRegime_weakness
    injury_impact
    rest_advantage
    altitude
    travel_fatigue
  ].freeze

  STANDARD_SIGNALS = %w[
    HIGH_EDGE_ML MID_EDGE_ML HIGH_EDGE_LOW_RISK
    STRONG_UP_FLOW COLLAPSE_FADE
    HOME_BIG_DOG LOW_TOTAL_UNDER
  ].freeze

  # structured_data 헬퍼 메서드
  def parsed_data
    @parsed_data ||= begin
      return {} if structured_data.blank?
      case structured_data
      when String then JSON.parse(structured_data) rescue {}
      when Hash then structured_data
      else {}
      end
    end
  end

  def triggers
    parsed_data['triggers'] || []
  end

  def signals
    parsed_data['signals'] || []
  end

  def edge_score
    parsed_data['edge_score']
  end

  def set_structured_data(triggers: [], signals: [], edge_score: nil, **extras)
    data = {
      'triggers' => triggers,
      'signals' => signals,
      'edge_score' => edge_score
    }.merge(extras.stringify_keys).compact

    self.structured_data = data.to_json
  end

  def add_trigger(trigger)
    data = parsed_data
    data['triggers'] ||= []
    data['triggers'] << trigger unless data['triggers'].include?(trigger)
    self.structured_data = data.to_json
  end

  def add_signal(signal)
    data = parsed_data
    data['signals'] ||= []
    data['signals'] << signal unless data['signals'].include?(signal)
    self.structured_data = data.to_json
  end

  after_commit :trigger_adcraft_media, if: :just_published?
  after_commit :trigger_telegram_broadcast, if: :just_published?
  after_commit :trigger_insight_generation, if: :just_published?

  def publish!
    update(status: "published", published_at: Time.current)
  end

  def published?
    status == "published"
  end

  def free?
    free == true
  end

  def premium?
    !free?
  end

  # Multi-Agent Consensus Logic
  def calculate_consensus!
    picks = [gpt_pick, gemini_pick, claude_pick].compact
    return if picks.empty?

    # Simple majority rule or strongest confidence
    tally = picks.tally
    self.consensus_pick = tally.max_by { |_k, v| v }.first
    save!
  end

  def gpt_pick
    extract_pick(gpt_analysis)
  end

  def gemini_pick
    extract_pick(gemini_analysis)
  end

  def claude_pick
    extract_pick(claude_analysis)
  end

  def confidence_stars
    confidence || "---"
  end

  private

  def just_published?
    saved_change_to_status? && status == "published"
  end

  def trigger_adcraft_media
    AdcraftTaskClient.enqueue_report_media!(self)
  rescue => e
    Rails.logger.error("[AdCraft] Failed to trigger media for Report ##{id}: #{e.message}")
    # Don't raise - AdCraft being down must not block report publishing
  end

  def trigger_telegram_broadcast
    TelegramPublisher.publish_report!(self)
  rescue => e
    Rails.logger.error("[Telegram] Failed to broadcast Report ##{id}: #{e.message}")
    # Don't raise - Telegram being down must not block report publishing
  end

  def trigger_insight_generation
    InsightGenerator.generate_from_report!(self)
  rescue => e
    Rails.logger.error("[InsightGenerator] Failed to generate insight for Report ##{id}: #{e.message}")
    # Don't raise - insight generation must not block report publishing
  end

  def extract_pick(analysis_text)
    return nil if analysis_text.blank?
    # Simple regex to find "PICK: XXX" pattern in the analysis
    match = analysis_text.match(/PICK:\s*(.+)$/)
    match ? match[1].strip : nil
  end

  # Result tracking methods
  def record_result!(result_value, home_score: nil, away_score: nil, note: nil)
    update!(
      result: result_value,
      result_recorded_at: Time.current,
      actual_home_score: home_score,
      actual_away_score: away_score,
      result_note: note
    )
  end

  def result_pending?
    result.nil? || result == "pending"
  end

  def result_recorded?
    !result_pending?
  end

  # Auto-calculate result based on scores (for spread/total)
  def calculate_result_from_scores(home_score, away_score)
    return nil unless pick_type.present? && pick_line.present?

    case pick_type
    when "spread"
      calculate_spread_result(home_score, away_score)
    when "total"
      calculate_total_result(home_score, away_score)
    when "moneyline"
      calculate_ml_result(home_score, away_score)
    end
  end

  # Class methods for stats
  class << self
    def stats(scope = all)
      records = scope.with_result
      total = records.count
      return empty_stats if total.zero?

      wins = records.wins.count
      losses = records.losses.count
      pushes = records.pushes.count

      # Calculate units (stake-weighted)
      units_won = records.wins.sum("COALESCE(stake, 1)")
      units_lost = records.losses.sum("COALESCE(stake, 1)")
      net_units = units_won - units_lost
      total_staked = records.sum("COALESCE(stake, 1)")

      {
        total: total,
        wins: wins,
        losses: losses,
        pushes: pushes,
        win_rate: (wins.to_f / [total - pushes, 1].max * 100).round(1),
        net_units: net_units.round(2),
        roi: total_staked.positive? ? ((net_units / total_staked) * 100).round(1) : 0.0
      }
    end

    def stats_by_pick_type(scope = all)
      PICK_TYPES.each_with_object({}) do |pick_type, hash|
        hash[pick_type] = stats(scope.where(pick_type: pick_type))
      end
    end

    def stats_by_consensus(scope = all)
      scope.with_result
           .group(:analyst_consensus)
           .pluck(:analyst_consensus)
           .compact
           .each_with_object({}) do |consensus, hash|
        hash[consensus] = stats(scope.where(analyst_consensus: consensus))
      end
    end

    def stats_by_month(scope = all)
      scope.with_result
           .group_by { |r| r.published_at&.strftime("%Y-%m") }
           .transform_values { |reports| stats(where(id: reports.map(&:id))) }
    end

    private

    def empty_stats
      { total: 0, wins: 0, losses: 0, pushes: 0, win_rate: 0.0, net_units: 0.0, roi: 0.0 }
    end
  end

  private

  def calculate_spread_result(home_score, away_score)
    margin = home_score - away_score
    # pick_side: "home" means betting home team, line is home spread
    adjusted_margin = pick_side == "home" ? margin + pick_line : -margin + pick_line

    if adjusted_margin > 0
      "win"
    elsif adjusted_margin < 0
      "loss"
    else
      "push"
    end
  end

  def calculate_total_result(home_score, away_score)
    total = home_score + away_score
    diff = total - pick_line

    if pick_side == "over"
      diff > 0 ? "win" : (diff < 0 ? "loss" : "push")
    else # under
      diff < 0 ? "win" : (diff > 0 ? "loss" : "push")
    end
  end

  def calculate_ml_result(home_score, away_score)
    home_won = home_score > away_score

    if pick_side == "home"
      home_won ? "win" : "loss"
    else
      home_won ? "loss" : "win"
    end
  end
end
