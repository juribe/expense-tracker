# frozen_string_literal: true

module PaymentEngine
  # Looks for purchases that were started (the user reached the provider) but
  # never completed and closes them out so a new payment can be started.
  # Pending purchases without a provider reference older than the grace window
  # are treated as abandoned. Pending purchases that do have a reference are
  # resolved against the provider's real transaction status first.
  class ReconcilePaymentsJob < ActiveJob::Base
    ABANDONMENT_WINDOW_MINUTES = 45

    def perform
      PaymentEngine::Purchase.pending_or_processing.where("created_at < ?", cutoff).find_each do |purchase|
        purchase.payment&.external_reference.present? ? reconcile_with_provider(purchase) : cancel_as_abandoned(purchase)
      end
    end

    private

    def cutoff
      ABANDONMENT_WINDOW_MINUTES.minutes.ago
    end

    def reconcile_with_provider(purchase)
      provider_code = purchase.payment.provider_code
      adapter = PaymentEngine.provider(provider_code) rescue nil
      result = adapter.fetch_payment(provider_transaction_id: purchase.payment.external_reference) if adapter
      state = mapped_state(result)

      ActiveRecord::Base.transaction do
        case state
        when "paid"
          purchase.update!(status: "paid")
          audit!(purchase, "payment.reconciled.paid", { status: "paid" })
        when "failed"
          purchase.update!(status: "failed")
          audit!(purchase, "payment.reconciled.failed", { status: "failed" })
        else
          cancel_as_abandoned(purchase)
        end
      end
    rescue StandardError => error
      audit!(purchase, "payment.reconciled.error", { error: error.message })
    end

    def mapped_state(result)
      return "unknown" unless result.respond_to?(:data) && result.data.is_a?(Hash)

      status = result.data["status"] || result.data[:status] || result.data["state"] || result.data[:state]
      case status.to_s
      when /paid|approved|aceptad|aprobad/i then "paid"
      when /rejected|failed|Rechazada|fallid/i then "failed"
      else "unknown"
      end
    end

    def cancel_as_abandoned(purchase)
      ActiveRecord::Base.transaction do
        purchase.update!(status: "cancelled")
        purchase.payment&.update!(status: "failed")
        audit!(purchase, "payment.reconciled.cancelled", { status: "cancelled" })
      end
    end

    def audit!(purchase, action, changes)
      PaymentEngine::AuditLog.create!(
        actor_type: "System",
        action: action,
        auditable_type: purchase.class.name,
        auditable_id: purchase.id,
        reason: nil,
        changes: changes,
        metadata: {}
      )
    end
  end
end
