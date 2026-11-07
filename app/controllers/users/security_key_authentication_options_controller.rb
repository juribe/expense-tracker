# frozen_string_literal: true

class Users::SecurityKeyAuthenticationOptionsController < Devise::SecurityKeyAuthenticationOptionsController
  prepend_before_action :ensure_pending_sign_in

  def create
    session[:two_factor_authentication_challenge_at] = Time.current.to_i
    super
  end

  private

  def ensure_pending_sign_in
    resource_id = session[:current_authentication_resource_id]
    return if resource_id.present? && resource_class.exists?(id: resource_id)

    set_flash_message! :alert, :sign_in_not_initiated, scope: :"devise.failure"
    redirect_to new_session_path(resource_name)
  end
end
