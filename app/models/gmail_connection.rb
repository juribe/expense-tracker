# frozen_string_literal: true

# A user's connected Gmail account (Google OAuth). OAuth tokens are stored
# encrypted at rest; #fresh_access_token! transparently refreshes them.
class GmailConnection < ApplicationRecord
  include EncryptedSecret

  TOKEN_EXPIRY_GRACE = 30.seconds

  belongs_to :user

  encrypts_secret :access_token
  encrypts_secret :refresh_token

  validates :email, presence: true, uniqueness: { scope: :user_id }
  validates :active, inclusion: { in: [ true, false ] }

  scope :active, -> { where(active: true) }

  def token_expired?
    return true if token_expires_at.blank?

    token_expires_at <= Time.current + TOKEN_EXPIRY_GRACE
  end

  # Returns a usable access token, refreshing it via Google when needed.
  def fresh_access_token!
    return access_token if access_token.present? && !token_expired?

    refresh_access_token!
  end

  def refresh_access_token!
    raise ArgumentError, "no refresh token stored" if refresh_token.blank?

    tokens = Gmail::OauthClient.refresh(refresh_token)
    self.access_token = tokens[:access_token]
    self.token_expires_at = tokens[:expires_at] || (Time.current + 1.hour)
    self.refresh_token = tokens[:refresh_token] if tokens[:refresh_token].present?
    save!
    access_token
  end

  # Normalized search criteria hash used by Gmail::QueryBuilder.
  def search_config_hash
    config = search_config.is_a?(Hash) ? search_config.deep_symbolize_keys : {}
    {
      senders: Array(config[:senders]).map(&:to_s).map(&:strip).reject(&:blank?),
      domains: Array(config[:domains]).map(&:to_s).map(&:strip).reject(&:blank?),
      subject_keywords: Array(config[:subject_keywords]).map(&:to_s).map(&:strip).reject(&:blank?)
    }
  end
end
