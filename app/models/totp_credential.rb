# frozen_string_literal: true

# A user's TOTP second factor. The shared secret is encrypted at rest with
# Active Record Encryption; only the encrypted column is persisted. The
# last_used_timestamp prevents replaying a code that was already accepted.
class TotpCredential < ApplicationRecord
  ISSUER = "Yogasto"
  DRIFT_SECONDS = 30
  SECRET_LENGTH = 32

  belongs_to :user

  encrypts :secret

  validates :secret, presence: true
  validates :user_id, uniqueness: true

  class << self
    def generate_secret
      ROTP::Base32.random_base32(SECRET_LENGTH)
    end
  end

  def provisioning_uri
    totp.provisioning_uri(user.email)
  end

  # Returns the matched Unix timestamp for a valid code, without consuming it.
  # `after` prevents accepting a time step that was already used.
  def verify_code(code, at: Time.current)
    normalized_code = code.to_s.gsub(/\s+/, "")
    return nil unless normalized_code.match?(/\A\d{6}\z/)

    totp.verify(
      normalized_code,
      drift_behind: DRIFT_SECONDS,
      drift_ahead: DRIFT_SECONDS,
      after: last_used_timestamp.to_i,
      at: at
    )
  rescue ROTP::Base32::Base32Error, ArgumentError
    nil
  end

  # Verifies and atomically records the accepted time step. Two concurrent
  # requests cannot both consume the same code.
  def verify_and_consume!(code, at: Time.current)
    consumed = false

    with_lock do
      timestamp = verify_code(code, at: at)
      next unless timestamp

      update!(last_used_timestamp: timestamp.to_i)
      consumed = true
    end

    consumed
  rescue ActiveRecord::RecordNotFound
    false
  end

  private

  def totp
    ROTP::TOTP.new(secret, issuer: ISSUER)
  end
end
