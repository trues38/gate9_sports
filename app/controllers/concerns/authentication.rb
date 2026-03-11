module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :current_user, :signed_in?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def signed_in?
    current_user.present?
  end

  def require_authentication
    unless signed_in?
      store_location
      redirect_to sign_in_path, alert: "로그인이 필요합니다"
    end
  end

  def require_subscription
    unless current_user&.can_access_premium?
      redirect_to new_subscription_path, alert: "구독이 필요합니다"
    end
  end

  def start_new_session_for(user)
    reset_session
    session[:user_id] = user.id
    user.touch_sign_in!
  end

  def terminate_session
    reset_session
  end

  def store_location
    session[:return_to] = request.fullpath if request.get?
  end

  def redirect_back_or(default, **options)
    redirect_to(session.delete(:return_to) || default, **options)
  end
end
