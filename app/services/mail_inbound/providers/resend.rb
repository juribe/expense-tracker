# frozen_string_literal: true

module MailInbound
  module Providers
    # Resend provider.
    # Verifies Svix signatures and fetches email content from the Receiving API.
    class Resend < Base
      def provider_name
        "resend"
      end

      def valid_signature?(request)
        secret = ENV["RESEND_WEBHOOK_SECRET"].presence
        raise ConfigurationError, "RESEND_WEBHOOK_SECRET is not configured" if secret.blank?

        Svix::Webhook.new(secret).verify(request.raw_body, svix_headers(request))
        true
      rescue Svix::WebhookVerificationError
        false
      end

      def build_delivery(request)
        event = parse_event(request.raw_body)
        unless event["type"] == "email.received"
          raise InvalidPayload, "unsupported Resend event type"
        end

        data = event["data"]
        raise InvalidPayload, "missing email data" unless data.is_a?(Hash)

        email_id = data["email_id"].to_s.presence
        raise InvalidPayload, "missing email_id" if email_id.blank?

        recipient = Array(data["to"]).first.to_s
        user = RecipientResolver.new(recipient: recipient).user

        DeliveryDraft.new(
          provider: provider_name,
          external_id: email_id,
          raw_body: request.raw_body,
          headers: {
            "content_type" => request.content_type,
            "recipient" => recipient
          }.compact,
          params: event,
          user: user
        )
      end

      def handle_email(delivery)
        event = delivery.params.is_a?(Hash) ? delivery.params : parse_event(delivery.raw_body)
        data = event["data"] || {}
        email = ReceivingClient.new.fetch(delivery.external_id)

        Message.new(
          provider: provider_name,
          external_id: delivery.external_id,
          from: email["from"].presence || data["from"],
          to: Array(email["to"]).presence || Array(data["to"]),
          subject: email["subject"].presence || data["subject"],
          body_text: email["text"].to_s,
          html: email["html"].presence,
          headers: normalize_headers(email["headers"]),
          attachments: Array(email["attachments"]),
          internal_date: parse_time(email["created_at"] || data["created_at"]),
          recipient: (Array(data["to"]).first || delivery.headers["recipient"]).to_s,
          user: delivery.user
        )
      end

      private

      def svix_headers(request)
        {
          "svix-id" => request.header("svix-id"),
          "svix-timestamp" => request.header("svix-timestamp"),
          "svix-signature" => request.header("svix-signature")
        }
      end

      def parse_event(raw_body)
        JSON.parse(raw_body.to_s)
      rescue JSON::ParserError
        raise InvalidPayload, "invalid Resend JSON payload"
      end

      def normalize_headers(headers)
        return [] unless headers.is_a?(Hash)

        headers.map { |name, value| { "name" => name.to_s, "value" => value.to_s } }
      end

      def parse_time(value)
        return Time.current if value.blank?

        Time.zone.parse(value.to_s) || Time.current
      rescue ArgumentError, TypeError
        Time.current
      end
    end
  end
end
