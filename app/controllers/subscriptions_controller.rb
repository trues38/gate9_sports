class SubscriptionsController < ApplicationController
  before_action :require_authentication

  def new
    @plans = Subscription.ordered_plans
    @current_subscription = current_user.active_subscription
    @pending_subscription = current_user.subscriptions.pending_payment.order(payment_requested_at: :desc, created_at: :desc).first
    @premium_benefits = PlanCatalog.premium_benefits
  end

  def show
    @subscription = current_user.subscriptions.find(params[:id])
  end

  def create
    plan = params[:plan]

    unless Subscription.plans.key?(plan)
      redirect_to new_subscription_path, alert: "올바르지 않은 플랜입니다"
      return
    end

    if current_user.active_subscription.present?
      redirect_to profile_path, alert: "이미 활성 구독이 있습니다"
      return
    end

    @subscription = Subscription.create_payment_request!(
      user: current_user,
      plan: plan,
      request_metadata: {
        source_path: params[:source_path].presence || request.referer,
        user_agent: request.user_agent
      }.compact
    )

    @plan = plan
    @plan_info = Subscription.plan_for(plan)
    track_conversion_event(
      "payment_requested",
      subscription_id: @subscription.id,
      plan: @plan,
      amount: @plan_info[:price]
    )
    render :payment_info
  end

  # 관리자가 수동으로 구독 부여할 때 사용
  # POST /subscriptions/grant?user_id=1&plan=monthly
  def grant
    unless current_user.admin?
      redirect_to root_path, alert: "권한이 없습니다"
      return
    end

    user = User.find(params[:user_id])
    plan = params[:plan]

    subscription = Subscription.grant!(
      user: user,
      plan: plan,
      payment_method: "manual",
      note: "관리자 수동 부여 by #{current_user.email}"
    )

    redirect_to admin_reports_path, notice: "#{user.email}에게 #{subscription.plan_name} 구독 부여 완료"
  end
end
