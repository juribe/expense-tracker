# frozen_string_literal: true

class Users::PasskeysController < Devise::PasskeysController
  include SecurityReauthentication

  before_action :require_recent_reauthentication
  before_action :require_current_second_factor, only: :create, if: -> { resource.second_factor_enabled? }

  def new
    redirect_to security_settings_path
  end

  def create
    unless challenge_fresh?
      clear_challenge!
      set_flash_message! :alert, :webauthn_challenge_expired, scope: :"devise.failure"
      return redirect_to after_update_path
    end

    super
  rescue JSON::ParserError, TypeError
    set_flash_message! :alert, :passkey_verification_failed, scope: :"devise.failure"
    redirect_to after_update_path
  ensure
    clear_challenge!
  end

  def destroy
    passkey = resource.passkeys.find_by(id: params[:id])

    if passkey.nil?
      set_flash_message! :alert, :passkey_deletion_failed, scope: :"devise.failure"
    elsif passkey.destroy
      set_flash_message! :notice, :passkey_deleted
    else
      set_flash_message! :alert, :passkey_deletion_failed, scope: :"devise.failure"
    end

    redirect_to after_update_path
  end

  private

  def verify_and_save_passkey(passkey_from_params)
    passkey_from_params.verify(session[:webauthn_challenge], user_verification: true)

    resource.passkeys.create(
      external_id: passkey_from_params.id,
      name: params[:name].presence || t("security.passkeys.default_name"),
      public_key: passkey_from_params.public_key,
      sign_count: passkey_from_params.sign_count,
      authentication_factor: :first_factor
    )
  end

  def after_update_path
    security_settings_path
  end

  def challenge_fresh?
    session[:webauthn_challenge].present? && WebauthnChallenge.fresh?(session[:webauthn_challenge_at])
  end

  def clear_challenge!
    session.delete(:webauthn_challenge)
    session.delete(:webauthn_challenge_at)
  end
end
