# frozen_string_literal: true

class Users::PasswordsController < Devise::PasswordsController
  # Keep Devise's email-sending/token logic but render an inline success
  # confirmation on the Forgot Password screen instead of redirecting.
  def create
    self.resource = resource_class.send_reset_password_instructions(resource_params)
    yield resource if block_given?

    if successfully_sent?(resource)
      @success_notice = "We've emailed a reset link. Check your inbox."
      render :new
    else
      respond_with(resource)
    end
  end

  # Keep Devise's password-update logic but show an inline success
  # confirmation on the Reset Password screen (auto-redirect after 3s).
  def update
    self.resource = resource_class.reset_password_by_token(resource_params)
    yield resource if block_given?

    if resource.errors.empty?
      resource.unlock_access! if unlockable?(resource)

      if Devise.sign_in_after_reset_password
        flash_message = resource.active_for_authentication? ? :updated : :updated_not_active
        set_flash_message!(:notice, flash_message)
        sign_in(resource_name, resource)
      else
        set_flash_message!(:notice, :updated_not_active)
      end

      @success_notice = "Your password has been updated."
      render :edit
    else
      set_minimum_password_length
      respond_with resource, location: nil
    end
  end
end
