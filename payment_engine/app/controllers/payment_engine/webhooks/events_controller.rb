# frozen_string_literal: true

module PaymentEngine
  module Webhooks
    class EventsController < PaymentEngine::ApplicationController
      skip_before_action :verify_authenticity_token
      # no admin auth

      def create
        payment_engine_provider = params[:provider]
        payload = request.request_parameters rescue params.to_unsafe_h

        payment_engine_adapter = PaymentEngine.provider(payment_engine_provider) rescue nil

        # Only trust the provider-specific adapter for signature verification.
        if payment_engine_adapter.respond_to?(:verify_webhook)
          return head :unauthorized unless payment_engine_adapter.verify_webhook(payload: payload, headers: request.headers.to_h, raw_body: request.raw_post)
        end

        normalized = nil
        if payment_engine_adapter.respond_to?(:parse_webhook)
          normalized = payment_engine_adapter.parse_webhook(payload: payload, headers: request.headers.to_h, raw_body: request.raw_post)
          normalized = normalized.data if normalized.success?
        end
        normalized = (normalized.is_a?(Hash) ? normalized.deep_symbolize_keys : {})

        event = WebhookEvent.find_or_create_by!(
          provider_code: payment_engine_provider,
          external_id: (normalized[:event_id] || webhook_external_id(payload)).to_s
        ) do |record|
          record.event_type = normalized[:event_type] || payload["type"] || payload["event"] || "unknown"
          record.status = "received"
          record.payload = sanitize_payload(payload)
          record.received_at = Time.current
        end

        PaymentEngine::Webhooks::Process.call(webhook_event: event, data: normalized.empty? ? payload.deep_stringify_keys : normalized)
        head :ok
      rescue StandardError => e
        Rails.logger.error("Webhook error: #{e.message}")
        head :bad_request
      end

      private

      # ePayco notifications identify the transaction by its reference
      # (`x_ref_payco`) and invoice. Fall back to the same keys used by other
      # providers before using a random id, so repeated notifications for the
      # same payment stay idempotent.
      def webhook_external_id(payload)
        value = payload["id"] ||
                payload["event_id"] ||
                payload["reference"] ||
                payload["referencePayco"] ||
                payload["ref_payco"] ||
                payload["x_ref_payco"] ||
                payload["x_transaction_id"] ||
                payload["invoice"] ||
                payload["extra1"]
        value.presence || SecureRandom.uuid
      end

      def sanitize_payload(payload)
        return {} unless payload.is_a?(Hash)
        payload.deep_dup.tap do |h|
          %w[secret token password api_key].each { |k| h.delete(k) }
        end
      end
    end
  end
end
