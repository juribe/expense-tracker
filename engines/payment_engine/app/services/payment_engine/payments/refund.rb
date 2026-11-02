module PaymentEngine
  module Payments
    # Registers a refund (full or partial). Refund policy: a full refund revokes
    # access immediately when configuration.revoke_access_on_refund is enabled
    # (default). Partial refunds keep access. Every refund is recorded; financial
    # rows are never deleted.
    class Refund
      def self.call(payment:, amount: nil, reason: nil, metadata: {})
        new(payment: payment, amount: amount, reason: reason, metadata: metadata).call
      end

      def initialize(payment:, amount: nil, reason: nil, metadata: {})
        @payment = payment
        @amount = amount
        @reason = reason
        @metadata = metadata.to_h
      end

      def call
        return Result.failure(code: :not_found, errors: [ "payment not found" ]) if payment.blank?
        return Result.success(data: payment, code: :already_refunded) if payment.status == "refunded"
        unless payment.approved? || payment.status == "partially_refunded"
          return Result.failure(code: :invalid_state, errors: [ "only approved payments can be refunded" ])
        end

        full_refund = full_refund?

        Payment.transaction do
          payment.lock!
          payment.update!(
            status: full_refund ? "refunded" : "partially_refunded",
            metadata: payment.metadata.merge(metadata).merge("refund_reason" => reason)
          )

          revoke_access! if full_refund && PaymentEngine.configuration.revoke_access_on_refund
          payment.purchase.update!(status: "refunded") if full_refund
        end

        Events.publish_after_commit(:payment_refunded, payment: payment, purchase: payment.purchase)
        Result.success(data: payment)
      end

      private

      attr_reader :payment, :amount, :reason, :metadata

      def full_refund?
        amount.blank? || amount.to_i >= payment.amount.to_i
      end

      def revoke_access!
        membership = payment.membership || payment.purchase.membership
        return if membership.blank?

        membership.lock!
        membership.update!(status: "canceled", canceled_at: PaymentEngine.current_time)
        membership.subscriptions.renewable.find_each do |subscription|
          subscription.update!(status: "canceled", canceled_at: PaymentEngine.current_time)
        end
        Events.publish_after_commit(:membership_canceled, membership: membership)
      end
    end
  end
end
