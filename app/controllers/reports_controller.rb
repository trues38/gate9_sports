class ReportsController < ApplicationController
  def index
    @page = (params[:page] || 1).to_i
    @per_page = 20
    # Include both sport-scoped game reports AND non-game reports (daily_schedule, results_summary)
    game_reports = current_sport&.reports&.published || Report.none
    non_game_reports = Report.where(game_id: nil).published
    reports = Report.where(id: game_reports.select(:id)).or(Report.where(id: non_game_reports.select(:id)))

    # Filter by report type if specified
    reports = reports.where(report_type: params[:type]) if params[:type].present?

    @total_count = reports.count
    @reports = reports.order(published_at: :desc).offset((@page - 1) * @per_page).limit(@per_page)
    @free_reports = reports.where(free: true)
    @premium_reports = reports.where(free: false)
  end

  def show
    @report = Report.find(params[:id])
    @full_access = @report.free? || can_access_premium?

    unless @full_access
      track_conversion_event(
        "paywall_viewed",
        report_id: @report.id,
        sport: @report.game&.sport&.slug,
        plan_keys: Subscription.plans.keys
      )
    end

    if @report.game.present?
      report_scope = @report.game.sport.reports.published
      @sport_performance = Report.stats(report_scope)
      @recent_results = report_scope.with_result.order(result_recorded_at: :desc, published_at: :desc).limit(5)
    else
      @sport_performance = Report.stats(Report.published)
      @recent_results = Report.published.with_result.order(result_recorded_at: :desc, published_at: :desc).limit(5)
    end
  end

  private

  def can_access_premium?
    current_user&.can_access_premium? || session[:admin_authenticated]
  end

  def store_location
    session[:return_to] = request.fullpath if request.get?
  end
end
