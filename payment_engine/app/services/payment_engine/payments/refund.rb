# frozen_string_literal: true

module PaymentEngine
  module Payments
    class Refund
      def self.call(payment:, amount: nil, actor: nil, reason: nil)
        amount ||= payment.amount
        ActiveRecord::Base.transaction do
          payment.update!(status: "refunded")

          purchase = payment.purchase
          if purchase
            purchase.update!(status: "refunded") unless purchase.status == "refunded"
            Memberships::RevokeForRefund.call(purchase: purchase, actor: actor, reason: reason)
          end

          AuditLog.create!(
            actor_type: actor&.class&.name || "System",
            actor_id: actor&.id,
            action: "payment.refunded",
            auditable_type: payment.class.name,
            auditable_id: payment.id,
            reason: reason,
            changes: { status: "refunded", amount: amount },
            metadata: {}
          )
        end
        PaymentEngine::Result.new(success: true, record: payment)
      rescue StandardError => e
        PaymentEngine::Result.new(success: false, errors: [e.message])
      end
    end
  end
end
