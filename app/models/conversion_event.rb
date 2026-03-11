class ConversionEvent < ApplicationRecord
  EVENT_NAMES = %w[
    sign_up_completed
    paywall_viewed
    payment_requested
    payment_approved
  ].freeze

  belongs_to :user, optional: true

  validates :event_name, presence: true, inclusion: { in: EVENT_NAMES }

  def self.track!(event_name:, user: nil, path: nil, metadata: {})
    create!(
      event_name: event_name,
      user: user,
      path: path,
      metadata: metadata,
      occurred_at: Time.current
    )
  end
end
