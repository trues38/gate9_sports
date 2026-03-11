class Subscription < ApplicationRecord
  belongs_to :user

  STATUSES = %w[active expired cancelled pending_payment rejected].freeze
  PAYMENT_METHODS = %w[toss kakao manual].freeze

  validates :plan, presence: true, inclusion: { in: ->(subscription) { subscription.class.plans.keys } }
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :starts_at, :expires_at, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active") }
  scope :expired, -> { where(status: "expired") }
  scope :pending_payment, -> { where(status: "pending_payment") }
  scope :expiring_soon, -> { active.where("expires_at <= ?", 3.days.from_now) }

  before_validation :set_defaults, on: :create

  class << self
    def plans
      PlanCatalog.plans_by_key
    end

    def ordered_plans
      PlanCatalog.ordered_plans
    end

    def plan_for(plan)
      plans[plan.to_s]
    end

    def create_payment_request!(user:, plan:, request_metadata: {})
      plan_info = plan_for(plan)
      raise ArgumentError, "Invalid plan: #{plan}" unless plan_info

      pending_request = user.subscriptions.pending_payment.where(plan: plan).order(created_at: :desc).first
      attributes = {
        amount: plan_info[:price],
        payment_method: "manual",
        payment_requested_at: Time.current,
        request_metadata: request_metadata
      }

      return pending_request.tap { pending_request.update!(attributes) } if pending_request

      create!(
        user: user,
        plan: plan,
        status: "pending_payment",
        **attributes
      )
    end
  end

  # 수동 구독 생성 (관리자용)
  def self.grant!(user:, plan:, payment_method: "manual", note: nil)
    plan_info = plan_for(plan)
    raise ArgumentError, "Invalid plan: #{plan}" unless plan_info

    create!(
      user: user,
      plan: plan,
      amount: plan_info[:price],
      payment_method: payment_method,
      starts_at: Time.current,
      expires_at: Time.current + plan_info[:duration],
      status: "active",
      note: note
    )
  end

  def active?
    status == "active" && expires_at > Time.current
  end

  def expired?
    status == "expired" || (status == "active" && expires_at <= Time.current)
  end

  def days_remaining
    return 0 unless active?
    ((expires_at - Time.current) / 1.day).ceil
  end

  def plan_name
    self.class.plan_for(plan)&.dig(:name) || plan
  end

  def pending_payment?
    status == "pending_payment"
  end

  def rejected?
    status == "rejected"
  end

  def approve!(reviewed_by:, note: nil, payment_id: nil)
    plan_info = self.class.plan_for(plan)
    raise ArgumentError, "Invalid plan: #{plan}" unless plan_info

    transaction do
      user.subscriptions.active.where.not(id: id).update_all(
        status: "expired",
        expires_at: Time.current,
        updated_at: Time.current
      )

      update!(
        status: "active",
        starts_at: Time.current,
        expires_at: Time.current + plan_info[:duration],
        reviewed_at: Time.current,
        reviewed_by: reviewed_by,
        payment_id: payment_id.presence || self.payment_id,
        note: merge_note(note)
      )
    end
  end

  def reject!(reviewed_by:, note: nil)
    update!(
      status: "rejected",
      reviewed_at: Time.current,
      reviewed_by: reviewed_by,
      note: merge_note(note)
    )
  end

  # 만료 처리 (cron job에서 호출)
  def self.expire_outdated!
    active.where("expires_at <= ?", Time.current).update_all(status: "expired")
  end

  private

  def set_defaults
    self.starts_at ||= Time.current
    if plan.present? && expires_at.blank?
      self.expires_at = starts_at + (self.class.plan_for(plan)&.fetch(:duration, 0) || 0)
    end
    self.amount ||= self.class.plan_for(plan)&.dig(:price)
    self.payment_requested_at ||= Time.current if pending_payment?
  end

  def merge_note(extra_note)
    [note, extra_note].compact_blank.join("\n")
  end
end
