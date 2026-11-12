# frozen_string_literal: true

require "base64"
require "rqrcode"

class SecuritySettingsController < ApplicationController
  include SecurityReauthentication

  TOTP_SETUP_SESSION_KEY = :totp_setup
  TOTP_SETUP_TTL = 10.minutes

  before_action :require_recent_reauthentication,
                only: %i[
                  regenerate_recovery_codes disable_two_factor
                  start_totp_setup totp_setup cancel_totp_setup
                  confirm_totp disable_totp
                ]
  before_action :require_current_second_factor,
                only: %i[disable_totp disable_two_factor start_totp_setup]
  before_action :prevent_security_page_caching

  rate_limit to: 10, within: 1.minute, only: :reauthenticate,
             name: "security_reauthentication", store: RateLimitProxy.new
  rate_limit to: 10, within: 1.minute, only: :confirm_totp,
             name: "totp_setup_confirmation", store: RateLimitProxy.new

  def show
    unless security_reauthenticated?
      @page_title = t("security.reauthentication.locked_title")
      return render :locked
    end

    @page_title = t("security.title")
    @recovery_codes_plaintext = nil
    load_security_state
  end

  def reauthenticate
    if current_user.valid_password?(params[:current_password])
      mark_security_reauthenticated!
      redirect_to security_settings_path, notice: t("security.reauthentication.success")
    else
      redirect_to security_settings_path, alert: t("security.reauthentication.failure")
    end
  end

  def regenerate_recovery_codes
    unless current_user.second_factor_enabled?
      redirect_to security_settings_path, alert: t("security.recovery_codes.two_factor_required")
      return
    end

    @recovery_codes_plaintext = RecoveryCode.generate_for(current_user)
    load_security_state
    @page_title = t("security.title")
    flash.now[:notice] = t("security.recovery_codes.generated")
    render :show, status: :ok
  end

  def disable_two_factor
    unless current_user.second_factor_webauthn_credentials.exists?
      redirect_to security_settings_path, alert: t("security.two_factor.already_disabled")
      return
    end

    current_user.with_lock do
      current_user.second_factor_webauthn_credentials.destroy_all
      current_user.recovery_codes.delete_all unless current_user.totp_enabled?
    end

    redirect_to security_settings_path, notice: t("security.two_factor.disabled")
  end

  def start_totp_setup
    secret = TotpCredential.generate_secret
    session[TOTP_SETUP_SESSION_KEY] = {
      "secret" => secret,
      "started_at" => Time.current.to_i
    }

    redirect_to totp_setup_security_settings_path, notice: t("security.totp.setup_started")
  end

  def totp_setup
    setup = pending_totp_setup
    unless setup
      redirect_to security_settings_path, alert: t("security.totp.setup_expired")
      return
    end

    @totp_secret = setup["secret"]
    @totp_enabled = current_user.totp_enabled?
    @totp_provisioning_uri = TotpCredential.new(secret: @totp_secret, user: current_user).provisioning_uri
    @totp_qr_svg = RQRCode::QRCode.new(@totp_provisioning_uri).as_svg(
      module_size: 6,
      viewbox: true,
      use_path: true
    ).sub(/\A<\?xml.*?\?>/, "")
    @totp_qr_data_uri = "data:image/svg+xml;base64,#{Base64.strict_encode64(@totp_qr_svg)}"
    @page_title = t("security.totp.setup_title")
  end

  def cancel_totp_setup
    session.delete(TOTP_SETUP_SESSION_KEY)
    redirect_to security_settings_path, notice: t("security.totp.setup_cancelled")
  end

  def confirm_totp
    setup = pending_totp_setup
    unless setup
      redirect_to security_settings_path, alert: t("security.totp.setup_expired")
      return
    end

    credential = current_user.totp_credential || current_user.build_totp_credential
    credential.assign_attributes(secret: setup["secret"], last_used_timestamp: 0)
    timestamp = credential.verify_code(params[:totp_code])

    unless timestamp
      redirect_to totp_setup_security_settings_path, alert: t("security.totp.invalid_code")
      return
    end

    credential.last_used_timestamp = timestamp.to_i
    credential.save!
    session.delete(TOTP_SETUP_SESSION_KEY)
    @recovery_codes_plaintext = RecoveryCode.generate_for(current_user) if current_user.recovery_codes.unused.none?
    load_security_state
    @page_title = t("security.title")
    flash.now[:notice] = t("security.totp.enabled_notice")
    render :show, status: :ok
  end

  def disable_totp
    unless current_user.totp_enabled?
      redirect_to security_settings_path, alert: t("security.totp.not_enabled")
      return
    end

    current_user.with_lock do
      current_user.totp_credential&.destroy!
      current_user.recovery_codes.delete_all unless current_user.second_factor_webauthn_credentials.exists?
    end

    session.delete(TOTP_SETUP_SESSION_KEY)
    redirect_to security_settings_path, notice: t("security.totp.disabled_notice")
  end

  private

  # Removing or rotating a factor requires proving the current one, not only the
  # password reauthentication window.
  def require_current_second_factor
    # The first TOTP enrollment has no existing factor to prove.
    return if action_name == "start_totp_setup" && !current_user.totp_enabled?
    return if current_second_factor_valid?

    redirect_to security_settings_path, alert: t("security.second_factor.required")
  end

  def current_second_factor_valid?
    return true if current_user.totp_credential&.verify_and_consume!(params[:totp_code])
    return true if RecoveryCode.consume!(current_user, params[:recovery_code]).present?

    false
  end

  def pending_totp_setup
    setup = session[TOTP_SETUP_SESSION_KEY]
    return nil unless setup.is_a?(Hash)

    started_at = setup["started_at"].to_i
    expired = started_at.zero? || Time.zone.at(started_at) < TOTP_SETUP_TTL.ago

    if expired
      session.delete(TOTP_SETUP_SESSION_KEY)
      return nil
    end

    setup
  end

  def prevent_security_page_caching
    response.headers["Cache-Control"] = "no-store"
    response.headers["Pragma"] = "no-cache"
  end

  def load_security_state
    @passkeys = current_user.passkeys.order(created_at: :desc)
    @second_factor_credentials = current_user.second_factor_webauthn_credentials.order(created_at: :desc)
    @recovery_codes_remaining = current_user.recovery_codes.unused.count
    @totp_enabled = current_user.totp_enabled?
    @mfa_enabled = current_user.second_factor_enabled?
  end
end
