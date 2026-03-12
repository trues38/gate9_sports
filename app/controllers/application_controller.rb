class ApplicationController < ActionController::Base
  include Authentication

  # 기본적으로 인증 불필요 (공개 페이지)
  allow_unauthenticated_access

  before_action :set_locale
  before_action :set_current_sport
  before_action :set_current_league
  helper_method :current_sport, :sports, :current_league, :available_leagues

  private

  def track_conversion_event(event_name, metadata = {})
    ConversionEvent.track!(
      event_name: event_name,
      user: current_user,
      path: request.fullpath,
      metadata: metadata
    )
  end

  def set_locale
    I18n.locale = params[:locale] || cookies[:locale] || I18n.default_locale
    cookies[:locale] = I18n.locale if params[:locale].present?
  end

  def default_url_options
    { locale: I18n.locale }
  end

  def set_current_sport
    @current_sport = Sport.find_by(slug: params[:sport]) || Sport.find_by(slug: "basketball")
  end

  def set_current_league
    @current_league = params[:league]
  end

  def current_sport
    @current_sport
  end

  def current_league
    @current_league
  end

  def available_leagues
    return [] unless current_sport
    # 현재 종목에 속한 게임들 중 리그 정보가 있는 것들만 추출
    @available_leagues ||= current_sport.games.where.not(league: nil).distinct.pluck(:league, :league_name)
                                        .map { |slug, name| { slug: slug, name: name || slug.upcase } }
  end

  def sports
    @sports ||= Sport.active
  end
end
