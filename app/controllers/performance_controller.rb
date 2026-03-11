class PerformanceController < ApplicationController
  # Public page — no authentication required
  skip_before_action :authenticate_user!, raise: false

  def index
    base = Report.where(status: "published").with_result.includes(:game)

    # Overall stats
    @overall_stats = Report.stats(base)

    # Edge tier stats (uses structured_data->edge_score)
    @high_edge_stats  = edge_tier_stats(base, 80, 100)
    @mid_edge_stats   = edge_tier_stats(base, 60, 79)
    @low_edge_stats   = edge_tier_stats(base, 0, 59)

    # Monthly breakdown
    @monthly_stats = monthly_breakdown(base)

    # Recent results (last 20)
    @recent_results = base.order(published_at: :desc).limit(20)

    # Stats by pick type
    @stats_by_type = Report.stats_by_pick_type(base)
  end

  private

  def edge_tier_stats(scope, min, max)
    # edge_score is stored inside structured_data JSON
    # SQLite JSON extraction
    records = scope.select { |r| r.edge_score.present? && r.edge_score.to_f.between?(min, max) }
    Report.stats(Report.where(id: records.map(&:id)))
  end

  def monthly_breakdown(scope)
    scope.order(published_at: :asc)
         .group_by { |r| r.published_at&.strftime("%Y-%m") }
         .compact
         .transform_values { |reports| Report.stats(Report.where(id: reports.map(&:id))) }
         .sort
         .reverse
         .first(12)
         .to_h
  end
end
