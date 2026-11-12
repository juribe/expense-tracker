# frozen_string_literal: true

# PremiumIdentities::Normalizer
# Canonical form of every premium identifier before it is fingerprinted.
#
# Example: PremiumIdentities::Normalizer.call(identity_type: "account_email", value: " Me@Example.com ")
class PremiumIdentities::Normalizer
  GMAIL_DOMAINS = %w[gmail.com googlemail.com].freeze
  WHATSAPP_TYPE = "whatsapp"

  def self.call(identity_type:, value:)
    new(identity_type: identity_type, value: value).call
  end

  def initialize(identity_type:, value:)
    @identity_type = identity_type.to_s
    @value = value
  end

  def call
    return WhatsappIdentity.normalize(@value).presence if @identity_type == WHATSAPP_TYPE

    normalize_email
  end

  private

  def normalize_email
    email = @value.to_s.strip.downcase
    local, domain = email.split("@", 2)
    return email if local.blank? || domain.blank?
    return email unless GMAIL_DOMAINS.include?(domain)

    local = local.split("+", 2).first.delete(".")
    "#{local}@gmail.com"
  end
end
