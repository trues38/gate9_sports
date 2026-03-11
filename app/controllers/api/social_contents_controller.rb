class Api::SocialContentsController < ApplicationController
  skip_before_action :verify_authenticity_token
  
  def create
    # Find or create report based on game matchup
    game = find_game_by_matchup(params[:game_matchup])
    
    unless game
      render json: { error: "Game not found for matchup: #{params[:game_matchup]}" }, status: :not_found
      return
    end
    
    # Find or create report for this game
    report = game.reports.first_or_initialize(
      title: "#{params[:away_team]} @ #{params[:home_team]} Analysis",
      content: params[:description] || "AI-generated analysis",
      status: "published",
      published_at: Time.current,
      free: true  # Make sample content free for now
    )
    
    # Add social content
    report.twitter_thread = params[:twitter_thread]
    report.youtube_shorts_script = params[:youtube_shorts_script]
    report.instagram_images = params[:instagram_images]
    report.social_generated_at = Time.parse(params[:generated_at]) rescue Time.current
    
    if report.save
      render json: {
        id: report.id,
        game_id: game.id,
        matchup: "#{game.away_abbr} @ #{game.home_abbr}",
        twitter_tweets: report.twitter_thread&.length || 0,
        youtube_script_length: report.youtube_shorts_script&.length || 0,
        instagram_images_count: report.instagram_images&.length || 0,
        created_at: report.created_at,
        url: Rails.application.routes.url_helpers.report_url(
          report,
          sport: game.sport.name,
          host: "193.46.243.3"
        )
      }, status: :created
    else
      render json: { error: report.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  private
  
  def find_game_by_matchup(matchup_str)
    # Parse "76ers @ Cavaliers" or similar
    parts = matchup_str.split('@').map(&:strip)
    return nil unless parts.length == 2
    
    away_team = parts[0]
    home_team = parts[1]
    
    # Find game by team names (fuzzy match on abbreviations or full names)
    Game.where("DATE(game_date) >= DATE('now', '-7 days')")
        .where("away_team LIKE ? OR away_abbr LIKE ?", "%#{away_team}%", "%#{away_team}%")
        .where("home_team LIKE ? OR home_abbr LIKE ?", "%#{home_team}%", "%#{home_team}%")
        .order(game_date: :desc)
        .first
  end
end
