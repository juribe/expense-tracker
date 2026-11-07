# frozen_string_literal: true

class Users::TotpAuthenticationsController < DeviseController
  include SecondFactorAuthentication

  rate_limit to: 100, within: 1.minute, only: :create, name: "totp",
             store: RateLimitProxy.new, if: -> { !Rails.env.production? }
  rate_limit to: 10, within: 1.minute, only: :create, name: "totp",
             store: RateLimitProxy.new, if: -> { Rails.env.production? }

  def create
    resource = pending_resource
    credential = resource&.totp_credential

    if credential&.verify_and_consume!(params[:totp_code])
      complete_sign_in(resource)
    else
      set_flash_message! :alert, :invalid_totp_code, scope: :"devise.failure"
      redirect_to new_user_two_factor_authentication_path
    end
  end
end
