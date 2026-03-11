class Admin::SubscriptionsController < Admin::BaseController
  before_action :set_subscription, only: [:approve, :reject]

  def index
    @pending_subscriptions = Subscription.pending_payment.includes(:user).order(payment_requested_at: :desc, created_at: :desc)
    @recently_reviewed = Subscription.where(status: %w[active rejected cancelled expired])
                                     .where.not(reviewed_at: nil)
                                     .includes(:user)
                                     .order(reviewed_at: :desc)
                                     .limit(20)
  end

  def approve
    @subscription.approve!(reviewed_by: "admin_session")
    ConversionEvent.track!(
      event_name: "payment_approved",
      user: @subscription.user,
      path: admin_subscriptions_path,
      metadata: {
        subscription_id: @subscription.id,
        plan: @subscription.plan
      }
    )

    redirect_to admin_subscriptions_path, notice: "#{@subscription.user.email} 결제 요청을 승인했습니다."
  end

  def reject
    @subscription.reject!(reviewed_by: "admin_session")
    redirect_to admin_subscriptions_path, notice: "#{@subscription.user.email} 결제 요청을 반려했습니다."
  end

  private

  def set_subscription
    @subscription = Subscription.find(params[:id])
  end
end
