class DashboardController < ApplicationController
  def index
    Time.use_zone("Asia/Seoul") do
      @today = Date.current
      start_of_day = @today.in_time_zone("Asia/Seoul").beginning_of_day
      end_of_day = @today.in_time_zone("Asia/Seoul").end_of_day

      # All sports with today's games, grouped by sport
      @sports_with_games = Sport.where(active: true).order(:position).filter_map do |sport|
        games = sport.games.where(game_date: start_of_day..end_of_day).order(:game_date).includes(:reports)
        next if games.empty?

        { sport: sport, games: games }
      end

      # Today's published reports (all sports)
      @recent_reports = Report.where(status: "published")
                              .order(published_at: :desc)
                              .limit(5)
    end
  end
end
