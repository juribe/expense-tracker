# frozen_string_literal: true

class Users::PasskeyRegistrationOptionsController < Devise::PasskeyRegistrationOptionsController
  include SecurityReauthentication

  before_action :require_recent_reauthentication

  def create
    session[:webauthn_challenge_at] = Time.current.to_i
    super
  end

  private

  def require_recent_reauthentication
    return if security_reauthenticated?

    render json: { error: t("security.reauthentication.required") }, status: :forbidden
  end
end
