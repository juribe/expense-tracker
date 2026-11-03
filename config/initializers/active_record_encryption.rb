# frozen_string_literal: true

require "digest"

# ActiveRecord Encryption keys for provider credentials and settings.
#
# Production must provide all three keys through environment variables (or
# encrypted credentials). Development and test derive deterministic keys from
# the local secret key base so the suite and local databases work without extra
# configuration.
credential_keys = begin
  Rails.application.credentials[:active_record_encryption] || {}
rescue StandardError
  {}
end

primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].presence || credential_keys[:primary_key].presence
deterministic_key = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].presence || credential_keys[:deterministic_key].presence
key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].presence || credential_keys[:key_derivation_salt].presence

if primary_key.blank? || deterministic_key.blank? || key_derivation_salt.blank?
  if Rails.env.production?
    raise <<~MESSAGE.squish
      Missing ActiveRecord Encryption keys.
      Set ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY,
      ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY and
      ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT.
    MESSAGE
  end

  secret = Rails.application.secret_key_base.presence || "expense-tracker-development-encryption"
  primary_key ||= Digest::SHA256.hexdigest("#{secret}:active_record_encryption:primary_key")
  deterministic_key ||= Digest::SHA256.hexdigest("#{secret}:active_record_encryption:deterministic_key")
  key_derivation_salt ||= Digest::SHA256.hexdigest("#{secret}:active_record_encryption:key_derivation_salt")
end

ActiveRecord::Encryption.configure(
  primary_key: primary_key,
  deterministic_key: deterministic_key,
  key_derivation_salt: key_derivation_salt,
  # Existing provider rows were stored as plaintext jsonb before encryption was
  # enabled. This allows them to be read (and re-encrypted on save) during the
  # transition without blocking the application.
  support_unencrypted_data: true
)
