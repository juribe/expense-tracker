# frozen_string_literal: true

class Users::SecondFactorWebauthnCredentialsController < Devise::SecondFactorWebauthnCredentialsController
  include SecurityReauthentication

  before_action :require_recent_reauthentication
  before_action :ensure_challenge_fresh, only: :create

  def new
    redirect_to security_settings_path
  end

  def create
    super
  rescue JSON::ParserError, TypeError
    set_flash_message! :alert, :webauthn_credential_verification_failed, scope: :"devise.failure"
    redirect_to after_create_path
  ensure
    clear_challenge!
  end

  # Promoting a second factor to a passkey would silently disable 2FA. The
  # product keeps those concepts separate, so this action is intentionally
  # blocked.
  def update
    set_flash_message! :alert, :security_key_promotion_failed, scope: :"devise.failure"
    redirect_to after_update_path
  end

  def destroy
    outcome = nil

    resource.with_lock do
      credential = resource.second_factor_webauthn_credentials.find_by(id: params[:id])

      outcome =
        if credential.nil?
          :not_found
        elsif resource.second_factor_webauthn_credentials.count <= 1
          :last_credential
        elsif credential.destroy
          :deleted
        else
          :failed
        end
    end

    set_deletion_flash(outcome)
    redirect_to after_destroy_path
  end

  private

  def set_deletion_flash(outcome)
    case outcome
    when :deleted
      set_flash_message! :notice, :security_key_deleted
    when :last_credential
      set_flash_message! :alert, :last_security_key, scope: :"devise.failure"
    else
      set_flash_message! :alert, :security_key_deletion_failed, scope: :"devise.failure"
    end
  end

  def verify_and_save_security_key(security_key_from_params)
    security_key_from_params.verify(session[:webauthn_challenge])

    resource.second_factor_webauthn_credentials.create(
      external_id: security_key_from_params.id,
      name: params[:name].presence || t("security.two_factor.default_name"),
      public_key: security_key_from_params.public_key,
      sign_count: security_key_from_params.sign_count,
      authentication_factor: :second_factor
    )
  end

  def ensure_challenge_fresh
    return if session[:webauthn_challenge].present? && WebauthnChallenge.fresh?(session[:webauthn_challenge_at])

    clear_challenge!
    set_flash_message! :alert, :webauthn_challenge_expired, scope: :"devise.failure"
    redirect_to security_settings_path
  end

  def clear_challenge!
    session.delete(:webauthn_challenge)
    session.delete(:webauthn_challenge_at)
  end

  def after_create_path
    security_settings_path
  end

  def after_update_path
    security_settings_path
  end

  def after_destroy_path
    security_settings_path
  end
end
