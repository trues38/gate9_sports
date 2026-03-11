class RegistrationsController < ApplicationController
  # Authentication은 ApplicationController에서 상속됨 (allow_unauthenticated_access 기본)

  def new
    redirect_to root_path if signed_in?
    @user = User.new
  end

  def create
    @user = User.new(user_params)

    if @user.save
      start_new_session_for(@user)
      track_conversion_event("sign_up_completed", user_id: @user.id)
      redirect_to root_path, notice: "회원가입이 완료되었습니다"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation, :name)
  end
end
