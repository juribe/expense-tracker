# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
  # Devise probes Warden in require_no_authentication before the create action.
  # That probe can run the passkey strategy and consume the one-time challenge
  # before the real authenticate! call. Guard signed-in users from the session
  # instead and let create perform the single authentication attempt.
  before_action :redirect_authenticated_users, only: :create

  def require_no_authentication
    return if action_name == "create"

    super
  end

  # Warden's failure app re-renders the sign-in form with 422 when a passkey is
  # unknown or belongs to someone else. Those are authentication failures, not
  # invalid forms, so send the visitor back to sign in with a clear message.
  def create
    return super if params[:public_key_credential].blank?

    resource = warden.authenticate(auth_options)

    if resource
      set_flash_message!(:notice, :signed_in)
      sign_in(resource_name, resource)
      respond_with resource, location: after_sign_in_path_for(resource)
    else
      redirect_to new_user_session_path, alert: t("devise.failure.passkey_not_found")
    end
  rescue JSON::ParserError, TypeError
    redirect_to new_user_session_path, alert: t("devise.failure.passkey_not_found")
  end

  def after_sign_in_path_for(resource)
    if session[:trial_intent] || session[:pending_payment_option_id]
      plans_path
    else
      super
    end
  end

  def destroy
    session.delete(:security_reauthenticated_at)
    super
  end

  private

  def redirect_authenticated_users
    return if session["warden.user.user.key"].blank?

    user = warden.user(resource_name)
    return if user.blank?

    redirect_to after_sign_in_path_for(user)
  end

  # Credential guessing is the cheapest attack on the app: check the counter
  # before Devise validates anything. The counter must not depend on the user
  # (a wrong guess must not be able to lock someone out), so it is per IP:
  # limits are loose in dev, strict in production. Names keep the two branch
  # definitions from sharing one rate-limit key.
  rate_limit to: 100, within: 1.minute, only: :create, name: "login",
             store: RateLimitProxy.new, if: -> { !Rails.env.production? }
  rate_limit to: 10, within: 1.minute, only: :create, name: "login",
             store: RateLimitProxy.new, if: -> { Rails.env.production? }
end
