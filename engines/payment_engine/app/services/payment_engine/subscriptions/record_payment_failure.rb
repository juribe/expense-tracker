module PaymentEngine
  module Subscriptions
    # Records a failed recurring charge. The subscription moves to past_due and
    # the configured grace period is applied once per billing period. Access is
    # not revoked immediately; the expiration job handles the final state.
    class RecordPaymentFailure
      def self.call(subscription:, failure_reason: nil, provider_transaction_id: nil,
                    amount: nil, currency: nil, paid_at: nil, metadata: {})
        new(
          subscription: subscription,
          failure_reason: failure_reason,
          provider_transaction_id: provider_transaction_id,
          amount: amount,
          currency: currency,
          paid_at: paid_at,
          metadata: metadata
        ).call
      end

      def initialize(subscription:, failure_reason: nil, provider_transaction_id: nil,
                     amount: nil, currency: nil, paid_at: nil, metadata: {})
        @subscription = subscription
        @failure_reason = failure_reason
        @provider_transaction_id = provider_transaction_id
        @amount = amount
        @currency = currency
        @paid_at = paid_at
        @metadata = metadata.to_h
      end

      def call
        return Result.failure(code: :not_found, errors: [ "subscription not found" ]) if subscription.blank?

        existing = find_existing_payment
        return Result.success(data: existing, code: :already_processed) if existing

        outcome = nil

        PaymentEngine::Subscription.transaction do
          subscription.lock!
          membership = subscription.membership
          membership.lock!

          existing = find_existing_payment
          if existing
            outcome = Result.success(data: existing, code: :already_processed)
            next
          end

          purchase = create_purchase(membership)
          payment = create_payment(purchase, membership)
          subscription.update!(status: "past_due")
          apply_grace_period(membership)
          purchase.update!(status: "failed")

          outcome = Result.success(data: payment, code: :payment_failed)
        end

        Events.publish_after_commit(:subscription_payment_failed, subscription: subscription,
                                                                  payment: outcome&.data) if outcome&.success?
        outcome
      rescue ActiveRecord::RecordNotUnique
        existing = find_existing_payment
        return Result.success(data: existing, code: :already_processed) if existing

        Result.failure(code: :duplicate_transaction, errors: [ "failure transaction was already recorded" ])
      rescue ActiveRecord::RecordInvalid => error
        Result.failure(code: :invalid_record, errors: error.record.errors.full_messages)
      end

      private

      attr_reader :subscription, :failure_reason, :provider_transaction_id, :amount,
                  :currency, :paid_at, :metadata

      def find_existing_payment
        return if provider_transaction_id.blank?

        Payment.find_by(provider: subscription.provider, provider_transaction_id: provider_transaction_id)
      end

      def create_purchase(membership)
        Purchase.create!(
          owner: membership.owner,
          payment_option: subscription.payment_option,
          membership: membership,
          provider: subscription.provider,
          status: "pending",
          price: subscription.effective_price,
          amount: subscription.effective_price,
          currency: subscription.effective_currency,
          billing_type: subscription.effective_billing_type,
          duration: subscription.duration_object.to_h,
          description: "Failed renewal of #{subscription.payment_option.name}",
          metadata: metadata.merge("subscription_id" => subscription.id, "renewal" => true)
        )
      end

      def create_payment(purchase, membership)
        purchase.payments.create!(
          provider: subscription.provider,
          membership: membership,
          amount: amount.present? ? amount.to_i : purchase.amount,
          currency: currency.presence || purchase.currency,
          status: "rejected",
          provider_transaction_id: provider_transaction_id,
          paid_at: paid_at,
          failure_reason: failure_reason.presence || "recurring payment failed",
          metadata: metadata
        )
      end

      def apply_grace_period(membership)
        grace = PaymentEngine.configuration.expiration_grace_period
        return if grace.zero?

        marker = subscription.current_period_ends_at&.iso8601
        return if marker.present? && membership.metadata["grace_applied_period"] == marker

        base = [ membership.expires_at, PaymentEngine.current_time ].compact.max
        membership.update!(
          expires_at: base + grace,
          metadata: membership.metadata.merge("grace_applied_period" => marker)
        )
      end
    end
  end
end
