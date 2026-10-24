# frozen_string_literal: true

class Users::RegistrationsController < Devise::RegistrationsController
  # Devise's default update_resource always demands the current password,
  # even for name-only edits. Only password/e-mail changes keep the
  # confirmation; a blank password updates the remaining profile freely.
  protected

  def update_resource(resource, params)
    if sensitive_change?(resource, params)
      resource.update_with_password(params)
    else
      safe_params = params.except(:password, :password_confirmation, :current_password)
      resource.update(safe_params)
    end
  end

  private

  def sign_up_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation)
  end

  def sensitive_change?(resource, params)
    email_changing = params[:email].present? && params[:email] != resource.email
    password_changing = params[:password].present? || params[:password_confirmation].present?

    email_changing || password_changing
  end

  def account_update_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation, :current_password)
  end
end
