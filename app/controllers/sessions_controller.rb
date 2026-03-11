class SessionsController < ApplicationController
  # Authentication은 ApplicationController에서 상속됨 (allow_unauthenticated_access 기본)

  # Rate limit: 5 attempts per minute
  rate_limit to: 5, within: 1.minute, only: :create,
             with: -> { redirect_to sign_in_path, alert: "너무 많은 시도입니다. 잠시 후 다시 시도해주세요." }

  def new
    redirect_to root_path if signed_in?
  end

  def create
    user = User.find_by(email: params[:email])

    if user&.authenticate(params[:password])
      start_new_session_for(user)
      redirect_back_or root_path, notice: "로그인되었습니다"
    else
      flash.now[:alert] = "이메일 또는 비밀번호가 올바르지 않습니다"
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    terminate_session
    redirect_to root_path, notice: "로그아웃되었습니다"
  end
end
