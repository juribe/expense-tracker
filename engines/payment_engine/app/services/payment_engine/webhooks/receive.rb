module PaymentEngine
  module Webhooks
    # Validates authenticity, stores the event once and enqueues processing.
    # Heavy financial work never runs inside the HTTP request.
    class Receive
      def self.call(provider_name:, payload:, headers: {}, raw_body: nil)
        new(provider_name: provider_name, payload: payload, headers: headers, raw_body: raw_body).call
      end

      def initialize(provider_name:, payload:, headers: {}, raw_body: nil)
        @provider_name = provider_name
        @payload = payload
        @headers = headers
        @raw_body = raw_body
      end

      def call
        adapter = PaymentEngine.provider(provider_name)

        unless adapter.verify_webhook(payload: payload, headers: headers, raw_body: raw_body)
          return Result.failure(code: :invalid_signature, errors: [ "invalid webhook signature" ])
        end

        parsed = adapter.parse_webhook(payload: payload, headers: headers, raw_body: raw_body)
        return parsed unless parsed.success?

        normalized = parsed.data.to_h.symbolize_keys
        event_type = normalized[:event_type].to_s
        return Result.failure(code: :malformed_event, errors: [ "webhook event type is missing" ]) if event_type.blank?

        event_id = normalized[:event_id].presence || fallback_event_id
        existing = WebhookEvent.find_by(provider: adapter.name.to_s, event_id: event_id)
        return Result.success(data: existing, code: :duplicate) if existing

        event = WebhookEvent.create!(
          provider: adapter.name.to_s,
          event_id: event_id,
          event_type: event_type,
          payload: stored_payload(normalized),
          status: "received",
          received_at: PaymentEngine.current_time
        )

        ProcessJob.perform_later(event.id)
        Result.success(data: event, code: :received)
      rescue UnknownProviderError, ConfigurationError => error
        Result.failure(code: :unknown_provider, errors: [ error.message ])
      rescue ActiveRecord::RecordNotUnique
        existing = WebhookEvent.find_by(provider: provider_name.to_s, event_id: event_id)
        Result.success(data: existing, code: :duplicate)
      rescue ActiveRecord::RecordInvalid => error
        Result.failure(code: :invalid_event, errors: error.record.errors.full_messages)
      end

      private

      attr_reader :provider_name, :payload, :headers, :raw_body

      def stored_payload(normalized)
        redacted = PayloadRedactor.redact(payload)
        redacted.merge("_payment_engine" => PayloadRedactor.redact(normalized))
      end

      def fallback_event_id
        Digest::SHA256.hexdigest(JSON.generate(PayloadRedactor.redact(payload)))
      end
    end
  end
end
