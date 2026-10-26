# frozen_string_literal: true

require "digest"

module MailInbound
  module Providers
    # Cloudflare Email Worker provider.
    # Verifies the Worker HMAC and parses the raw RFC 5322/MIME body.
    class Cloudflare < Base
      ALLOWED_CONTENT_TYPES = %w[message/rfc822 application/octet-stream].freeze
      DEFAULT_MAX_BYTES = 10 * 1024 * 1024

      def provider_name
        "cloudflare"
      end

      def valid_signature?(request)
        secret = ENV["INBOUND_EMAIL_SECRET"].presence
        raise ConfigurationError, "INBOUND_EMAIL_SECRET is not configured" if secret.blank?

        SignatureVerifier.valid?(
          secret: secret,
          previous_secret: ENV["INBOUND_EMAIL_SECRET_PREVIOUS"].presence,
          timestamp: request.header("X-Cloudflare-Email-Timestamp"),
          recipient: request.header("X-Cloudflare-Email-Recipient"),
          signature: request.header("X-Cloudflare-Email-Signature"),
          body: request.raw_body,
          max_skew: ENV.fetch("INBOUND_EMAIL_MAX_SKEW_SECONDS", 300).to_i.clamp(30, 3600)
        )
      end

      def build_delivery(request)
        unless ALLOWED_CONTENT_TYPES.include?(request.content_type.to_s.split(";").first)
          raise UnsupportedMediaType, "unsupported content type"
        end
        raise PayloadTooLarge, "payload too large" if request.raw_body.to_s.bytesize > max_bytes

        recipient = request.header("X-Cloudflare-Email-Recipient")
        user = RecipientResolver.new(recipient: recipient).user
        external_id = Digest::SHA256.hexdigest(request.raw_body.to_s)

        DeliveryDraft.new(
          provider: provider_name,
          external_id: external_id,
          raw_body: request.raw_body,
          headers: {
            "content_type" => request.content_type,
            "from" => request.header("X-Cloudflare-Email-From"),
            "recipient" => recipient
          }.compact,
          params: {},
          user: user
        )
      end

      def handle_email(delivery)
        parsed = MessageParser.call(
          delivery.raw_body,
          envelope_from: delivery.headers["from"],
          envelope_to: delivery.headers["recipient"]
        )

        Message.new(
          provider: provider_name,
          external_id: delivery.external_id,
          from: parsed[:from],
          to: parsed[:to],
          subject: parsed[:subject],
          body_text: parsed[:body_text],
          html: parsed[:html],
          headers: parsed[:headers],
          attachments: parsed[:attachments],
          internal_date: parsed[:internal_date],
          recipient: delivery.headers["recipient"],
          user: delivery.user
        )
      end

      private

      def max_bytes
        ENV.fetch("INBOUND_EMAIL_MAX_BYTES", DEFAULT_MAX_BYTES).to_i.clamp(1, 25.megabytes)
      end
    end
  end
end
