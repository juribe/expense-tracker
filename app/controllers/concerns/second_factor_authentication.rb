# frozen_string_literal: true

# Shared sign-in completion for the second-factor controllers (TOTP and
# recovery codes). The password strategy stores the pending user in session
# and does not create a full Devise session until one of these controllers
# validates the second factor.
module SecondFactorAuthentication
  extend ActiveSupport::Concern

  included do
    prepend_before_action :ensure_pending_sign_in
    prepend_before_action :redirect_authenticated_users
  end

  private

  def redirect_authenticated_users
    return if session["warden.user.user.key"].blank?

    user = warden.user(resource_name)
    return if user.blank?

    redirect_to after_sign_in_path_for(user)
  end

  def pending_resource
    resource_class.find_by(id: session[:current_authentication_resource_id])
  end

  def complete_sign_in(resource)
    resource.remember_me = session[:current_authentication_remember_me] if resource.respond_to?(:remember_me=)
    clear_pending_authentication
    sign_in(resource_name, resource)
    set_flash_message! :notice, :signed_in, scope: :"devise.sessions"
    redirect_to after_sign_in_path_for(resource)
  end

  def clear_pending_authentication
    session.delete(:current_authentication_resource_id)
    session.delete(:current_authentication_remember_me)
    session.delete(:two_factor_authentication_challenge)
    session.delete(:two_factor_authentication_challenge_at)
  end

  def ensure_pending_sign_in
    return if session[:current_authentication_resource_id].present?

    set_flash_message! :alert, :sign_in_not_initiated, scope: :"devise.failure"
    redirect_to new_session_path(resource_name)
  end

  def after_sign_in_path_for(resource)
    if session[:trial_intent] || session[:pending_payment_option_id]
      plans_path
    else
      super
    end
  end
end
