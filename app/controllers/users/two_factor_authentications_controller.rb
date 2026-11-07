# frozen_string_literal: true

class Users::TwoFactorAuthenticationsController < Devise::TwoFactorAuthenticationsController
  # Devise's require_no_authentication probes Warden, which can run the
  # WebAuthn strategy before this action and consume the one-time challenge.
  # Guard signed-in users from the session instead and let the action perform
  # the single authenticate! call.
  before_action :redirect_authenticated_users, only: :create

  def require_no_authentication
    return if action_name == "create"

    super
  end

  def create
    unless challenge_fresh?
      clear_challenge!
      set_flash_message! :alert, :webauthn_challenge_expired, scope: :"devise.failure"
      return redirect_to new_user_two_factor_authentication_path
    end

    super
  rescue JSON::ParserError, TypeError
    set_flash_message! :alert, :webauthn_credential_verification_failed, scope: :"devise.failure"
    redirect_to new_user_two_factor_authentication_path
  ensure
    clear_challenge!
  end

  private

  def redirect_authenticated_users
    return if session["warden.user.user.key"].blank?

    user = warden.user(resource_name)
    return if user.blank?

    redirect_to after_sign_in_path_for(user)
  end

  def challenge_fresh?
    session[:two_factor_authentication_challenge].present? &&
      WebauthnChallenge.fresh?(session[:two_factor_authentication_challenge_at])
  end

  def clear_challenge!
    session.delete(:two_factor_authentication_challenge)
    session.delete(:two_factor_authentication_challenge_at)
  end
end
