# frozen_string_literal: true

class Users::RecoveryCodeAuthenticationsController < DeviseController
  include SecondFactorAuthentication

  rate_limit to: 100, within: 1.minute, only: :create, name: "recovery_code",
             store: RateLimitProxy.new, if: -> { !Rails.env.production? }
  rate_limit to: 10, within: 1.minute, only: :create, name: "recovery_code",
             store: RateLimitProxy.new, if: -> { Rails.env.production? }

  def create
    resource = pending_resource
    recovery_code = resource && RecoveryCode.consume!(resource, params[:recovery_code])

    if recovery_code
      complete_sign_in(resource)
    else
      set_flash_message! :alert, :invalid_recovery_code, scope: :"devise.failure"
      redirect_to new_user_two_factor_authentication_path
    end
  end
end
