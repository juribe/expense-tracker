# frozen_string_literal: true

module MailInbound
  PROVIDERS = {
    "cloudflare" => "MailInbound::Providers::Cloudflare",
    "resend" => "MailInbound::Providers::Resend"
  }.freeze

  class Error < StandardError; end
  class ConfigurationError < Error; end
  class InvalidPayload < Error; end
  class PayloadTooLarge < InvalidPayload; end
  class UnsupportedMediaType < InvalidPayload; end
  class UnknownRecipient < Error; end
  class ProviderError < Error; end
  class QueueError < Error; end

  class << self
    def provider_name
      name = ENV.fetch("MAIL_INBOUND_PROVIDER", "cloudflare").to_s.downcase
      raise ConfigurationError, "unknown MAIL_INBOUND_PROVIDER #{name.inspect}" unless PROVIDERS.key?(name)

      name
    end

    def provider_class(name = provider_name)
      PROVIDERS.fetch(name.to_s.downcase) { raise ConfigurationError, "unknown mail inbound provider" }.constantize
    end
  end
end
