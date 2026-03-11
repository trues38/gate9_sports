class User < ApplicationRecord
  has_secure_password
  has_many :subscriptions, dependent: :destroy

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :email, presence: true, uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 6 }, allow_nil: true

  ROLES = %w[user premium admin].freeze

  scope :admins, -> { where(role: "admin") }
  scope :premium_users, -> { where(role: "premium") }

  def admin?
    role == "admin"
  end

  def premium?
    role == "premium" || admin?
  end

  # 구독 상태 확인
  def active_subscription
    subscriptions.active.where("expires_at > ?", Time.current).order(expires_at: :desc).first
  end

  def subscribed?
    active_subscription.present?
  end

  # 프리미엄 리포트 접근 가능 여부
  def can_access_premium?
    admin? || premium? || subscribed?
  end

  def touch_sign_in!
    update_column(:last_sign_in_at, Time.current)
  end
end
