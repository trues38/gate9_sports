class ProfileController < ApplicationController
  def index
    @pending_subscription = current_user&.subscriptions&.pending_payment&.order(payment_requested_at: :desc, created_at: :desc)&.first
  end
end
