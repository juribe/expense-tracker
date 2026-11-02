module PaymentEngine
  module Payments
    # Records a rejected payment attempt. Rejected payments never grant access.
    # A purchase with no approved payment is marked failed.
    class Reject
      def self.call(payment:, failure_reason: nil, provider_transaction_id: nil, metadata: {})
        new(payment: payment, failure_reason: failure_reason,
            provider_transaction_id: provider_transaction_id, metadata: metadata).call
      end

      def initialize(payment:, failure_reason: nil, provider_transaction_id: nil, metadata: {})
        @payment = payment
        @failure_reason = failure_reason
        @provider_transaction_id = provider_transaction_id
        @metadata = metadata.to_h
      end

      def call
        return Result.failure(code: :not_found, errors: [ "payment not found" ]) if payment.blank?
        return Result.success(data: payment, code: :already_rejected) if payment.status == "rejected"
        return Result.failure(code: :invalid_state, errors: [ "an approved payment cannot be rejected" ]) if payment.approved?

        Payment.transaction do
          payment.lock!
          payment.update!(
            status: "rejected",
            failure_reason: failure_reason.presence || payment.failure_reason,
            provider_transaction_id: provider_transaction_id.presence || payment.provider_transaction_id,
            metadata: payment.metadata.merge(metadata)
          )

          purchase = payment.purchase
          purchase.lock!
          purchase.update!(status: "failed") unless purchase.completed? || purchase.payments.approved.exists?
        end

        Events.publish_after_commit(:payment_rejected, payment: payment, purchase: payment.purchase)
        Result.success(data: payment)
      end

      private

      attr_reader :payment, :failure_reason, :provider_transaction_id, :metadata
    end
  end
end
