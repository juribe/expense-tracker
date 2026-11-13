# frozen_string_literal: true

# Session-based reauthentication for sensitive account-security actions.
# A successful password check unlocks those actions for ten minutes.
module SecurityReauthentication
  extend ActiveSupport::Concern

  REAUTHENTICATION_WINDOW = 10.minutes
  SESSION_KEY = :security_reauthenticated_at

  included do
    helper_method :security_reauthenticated?
  end

  def security_reauthenticated?
    data = session[SESSION_KEY]
    return false unless data.is_a?(Hash)
    return false unless data["user_id"].to_s == current_user.id.to_s

    timestamp = data["at"]
    timestamp.present? && Time.zone.at(timestamp.to_i) >= REAUTHENTICATION_WINDOW.ago
  end

  def mark_security_reauthenticated!
    session[SESSION_KEY] = {
      "user_id" => current_user.id,
      "at" => Time.current.to_i
    }
  end

  def require_recent_reauthentication
    return if security_reauthenticated?

    redirect_to security_settings_path, alert: t("security.reauthentication.required")
  end

  # Verifies the factor the account already has (TOTP or a recovery code).
  def current_second_factor_valid?
    return true if current_user.totp_credential&.verify_and_consume!(params[:totp_code])
    return true if RecoveryCode.consume!(current_user, params[:recovery_code]).present?

    false
  end

  def require_current_second_factor
    return if current_second_factor_valid?

    redirect_to security_settings_path, alert: t("security.second_factor.required")
  end
end
