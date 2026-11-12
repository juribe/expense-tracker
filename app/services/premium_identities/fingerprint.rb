# frozen_string_literal: true

require "openssl"

# PremiumIdentities::Fingerprint
# Deterministic HMAC-SHA256 fingerprint of a normalized premium identifier.
# The secret never leaves the process, so a database leak cannot be reversed
# with a simple rainbow table.
#
# Example: PremiumIdentities::Fingerprint.call(identity_type: "account_email", value: email)
class PremiumIdentities::Fingerprint
  SECRET_ENV = "PREMIUM_IDENTITY_HMAC_SECRET"
  KEY_DERIVATION_NAMESPACE = "premium_identities/fingerprint"

  class << self
    def call(identity_type:, value:)
      normalized = PremiumIdentities::Normalizer.call(identity_type: identity_type, value: value)
      return nil if normalized.blank?

      OpenSSL::HMAC.hexdigest("SHA256", secret, "#{identity_type}:#{normalized}")
    end

    private

    def secret
      ENV[SECRET_ENV].presence || derived_secret
    end

    def derived_secret
      @derived_secret ||= Rails.application.key_generator.generate_key(KEY_DERIVATION_NAMESPACE, 32)
    end
  end
end
