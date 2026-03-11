class ReportsController < ApplicationController
  def index
    @page = (params[:page] || 1).to_i
    @per_page = 20
    reports = current_sport&.reports&.published || Report.none
    @total_count = reports.count
    @reports = reports.offset((@page - 1) * @per_page).limit(@per_page)
    @free_reports = reports.where(free: true)
    @premium_reports = reports.where(free: false)
  end

  def show
    @report = Report.find(params[:id])
    @full_access = @report.free? || can_access_premium?

    # Track paywall impression for premium reports without full access
    unless @full_access
      track_conversion_event(
        "paywall_viewed",
        report_id: @report.id,
        sport: @report.game.sport.slug,
        plan_keys: Subscription.plans.keys
      )
    end

    report_scope = @report.game.sport.reports.published
    @sport_performance = Report.stats(report_scope)
    @recent_results = report_scope.with_result.order(result_recorded_at: :desc, published_at: :desc).limit(5)
  end

  private

  def can_access_premium?
    current_user&.can_access_premium? || session[:admin_authenticated]
  end

  def store_location
    session[:return_to] = request.fullpath if request.get?
  end
end
