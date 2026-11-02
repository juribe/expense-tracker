# frozen_string_literal: true

module PaymentEngine
  module Webhooks
    class EventsController < PaymentEngine::ApplicationController
      skip_before_action :verify_authenticity_token
      # no admin auth

      def create
        provider = params[:provider]
        payload = request.request_parameters rescue params.to_unsafe_h
        external_id = payload["id"] || payload["event_id"] || payload["reference"] || SecureRandom.uuid
        event_type = payload["type"] || payload["event"] || "unknown"

        event = WebhookEvent.find_by(provider_code: provider, external_id: external_id)
        if event.nil?
          event = WebhookEvent.create!(
            provider_code: provider,
            external_id: external_id,
            event_type: event_type,
            status: "received",
            payload: sanitize_payload(payload),
            received_at: Time.current
          )
        end

        # process
        PaymentEngine::Webhooks::Process.call(webhook_event: event)
        head :ok
      rescue StandardError => e
        Rails.logger.error("Webhook error: #{e.message}")
        head :bad_request
      end

      private

      def sanitize_payload(payload)
        return {} unless payload.is_a?(Hash)
        payload.deep_dup.tap do |h|
          %w[secret token password api_key].each { |k| h.delete(k) }
        end
      end
    end
  end
end
