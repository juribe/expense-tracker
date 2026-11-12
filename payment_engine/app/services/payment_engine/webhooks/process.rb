# frozen_string_literal: true

module PaymentEngine
  module Webhooks
    # Processes a validated provider notification. ePayco-specific parsing and
    # signature verification live in the provider adapter; this service is
    # generic and applies the normalized event to PaymentEngine records.
    class Process
      EVENT_HANDLERS = {
        "payment.approved" => :handle_payment_approved,
        "payment.rejected" => :handle_payment_rejected,
        "payment.pending" => :handle_payment_pending,
        "payment.refunded" => :handle_payment_refunded
      }.freeze

      def self.call(webhook_event:, data: nil, actor: nil)
        new(webhook_event: webhook_event, data: data, actor: actor).call
      end

      def initialize(webhook_event:, data: nil, actor: nil)
        @webhook_event = webhook_event
        @data = data
        @actor = actor
      end

      def call
        if webhook_event.processed?
          return Result.new(success: true, record: webhook_event, metadata: { skipped: true })
        end

        event_data = payload_for_processing(@data)

        ActiveRecord::Base.transaction do
          outcome = process_event(event_data)

          webhook_event.update!(
            status: "processed",
            processed_at: Time.current,
            attempts: webhook_event.attempts.to_i + 1
          )
          audit!(
            action: "webhook.processed",
            auditable: webhook_event,
            changes: { status: "processed", event_type: event_data["event_type"].presence || "unknown" }
          )

          outcome || Result.new(success: true, record: webhook_event)
        end
      rescue StandardError => error
        webhook_event.update!(status: "failed", processing_result: error.message, attempts: webhook_event.attempts.to_i + 1) rescue nil
        Result.new(success: false, errors: [error.message])
      end

      private

      attr_reader :webhook_event, :actor

      # Accepts a normalized payload from the provider adapter or falls back to
      # the stored raw payload. Unknown providers only get the event recorded.
      def payload_for_processing(passthrough)
        if passthrough.is_a?(PaymentEngine::Result)
          passthrough = passthrough.data
        end
        return {} unless passthrough.is_a?(Hash)

        passthrough.deep_stringify_keys
      end

      def process_event(data)
        handler = EVENT_HANDLERS[data["event_type"]]
        return unless handler

        purchase = Purchase.find_by(id: data["purchase_id"])
        return unless purchase
        return unless amount_matches?(purchase, data) && currency_matches?(purchase, data)

        send(handler, purchase, data)
      end

      def handle_payment_approved(purchase, data)
        payment = purchase.payment || Payment.create!(purchase: purchase, amount: purchase.amount, currency: purchase.currency, status: "pending", provider_code: webhook_event.provider_code)
        payment.update!(
          provider_code: webhook_event.provider_code,
          external_reference: provider_reference_for(data),
          status: "succeeded"
        )
        purchase.update!(status: "paid", payment_id: payment.id)
        grant_membership(purchase)
        audit!(action: "payment.approved", auditable: purchase, changes: { status: "paid" })
        Result.new(success: true, record: payment)
      end

      def handle_payment_rejected(purchase, data)
        payment = purchase.payment || Payment.create!(purchase: purchase, amount: purchase.amount, currency: purchase.currency, status: "pending", provider_code: webhook_event.provider_code)
        payment.update!(
          provider_code: webhook_event.provider_code,
          external_reference: provider_reference_for(data),
          status: "failed"
        )
        purchase.update!(status: "failed")
        audit!(action: "payment.rejected", auditable: purchase, changes: { status: "failed" })
        Result.new(success: true, record: payment)
      end

      def handle_payment_pending(purchase, data)
        payment = purchase.payment || Payment.create!(purchase: purchase, amount: purchase.amount, currency: purchase.currency, status: "pending", provider_code: webhook_event.provider_code)
        payment.update!(
          provider_code: webhook_event.provider_code,
          external_reference: provider_reference_for(data)
        )
        audit!(action: "payment.pending", auditable: purchase, changes: { status: "pending" })
        Result.new(success: true, record: payment)
      end

      def handle_payment_refunded(purchase, data)
        payment = purchase.payment || Payment.create!(purchase: purchase, amount: purchase.amount, currency: purchase.currency, status: "pending", provider_code: webhook_event.provider_code)
        payment.update!(
          provider_code: webhook_event.provider_code,
          external_reference: provider_reference_for(data),
          status: "refunded"
        )
        purchase.update!(status: "refunded")
        Memberships::RevokeForRefund.call(purchase: purchase, actor: actor, reason: "refund")
        audit!(action: "payment.refunded", auditable: purchase, changes: { status: "refunded" })
        Result.new(success: true, record: payment)
      end

      def provider_reference_for(data)
        data.dig("metadata", "epayco_ref").presence ||
          data["provider_transaction_id"].presence ||
          data["event_id"]
      end


      def amount_matches?(purchase, data)
        expected = data["amount"]
        return true if expected.blank?

        purchase.amount == BigDecimal(expected.to_s)
      rescue ArgumentError, TypeError
        false
      end

      def currency_matches?(purchase, data)
        expected = data["currency"]
        return true if expected.blank?

        purchase.currency.to_s.casecmp(expected.to_s).zero?
      end

      def grant_membership(purchase)
        Memberships::FulfillPurchase.call(purchase: purchase)
      end

      def audit!(action:, auditable:, changes:)
        AuditLog.create!(
          actor_type: actor&.class&.name || "System",
          actor_id: actor&.id,
          action: action,
          auditable_type: auditable.class.name,
          auditable_id: auditable.id,
          reason: nil,
          changes: changes,
          metadata: {}
        )
      end
    end
  end
end
