class PromaxController < ApplicationController
  def index
    # Default to basketball if no sport param (since we are outside the sport scope usually, or we can use param)
    # But ApplicationController might need params[:sport] to set current_sport.
    # Let's handle it safely.
    
    Time.use_zone("Asia/Seoul") do
      @selected_date = parse_date_safely(params[:date]) || Date.current
      start_of_day = @selected_date.in_time_zone("Asia/Seoul").beginning_of_day
      end_of_day = @selected_date.in_time_zone("Asia/Seoul").end_of_day

      # Ensure current_sport is set (if ApplicationController relies on params[:sport], we might need to pretend or force it)
      # If current_sport is nil, default to first sport or handle error
      sport = current_sport || Sport.find_by(slug: 'basketball') 

      if sport
        @games = sport.games
                      .where(game_date: start_of_day..end_of_day)
                      .order(:game_date)
        
        @filter = params[:filter] || "all"
        case @filter
        when "b2b"
          @games = @games.where("schedule_note LIKE ?", "%B2B%")
        when "3in4"
          @games = @games.where("schedule_note LIKE ?", "%3in4%")
        when "edge"
          @games = @games.where.not(schedule_note: [nil, ""])
        end

        @total_games = sport.games.where(game_date: start_of_day..end_of_day).count
        @edge_games = sport.games.where(game_date: start_of_day..end_of_day).where.not(schedule_note: [nil, ""]).count
      else
        @games = []
      end
    end
    
    render layout: "promax"
  end

  private

  def parse_date_safely(date_string)
    return nil if date_string.blank?
    Date.parse(date_string)
  rescue ArgumentError, TypeError
    nil
  end
end
