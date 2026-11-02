module PaymentEngine
  module Subscriptions
    # Records a confirmed recurring renewal. The extension uses the provider's
    # billed period when available, never the webhook reception time, and never
    # extends twice for the same provider transaction.
    class RecordRenewal
      def self.call(subscription:, provider_transaction_id:, amount: nil, currency: nil,
                    paid_at: nil, period_starts_at: nil, period_ends_at: nil, metadata: {})
        new(
          subscription: subscription,
          provider_transaction_id: provider_transaction_id,
          amount: amount,
          currency: currency,
          paid_at: paid_at,
          period_starts_at: period_starts_at,
          period_ends_at: period_ends_at,
          metadata: metadata
        ).call
      end

      def initialize(subscription:, provider_transaction_id:, amount: nil, currency: nil,
                     paid_at: nil, period_starts_at: nil, period_ends_at: nil, metadata: {})
        @subscription = subscription
        @provider_transaction_id = provider_transaction_id
        @amount = amount
        @currency = currency
        @paid_at = paid_at
        @period_starts_at = period_starts_at
        @period_ends_at = period_ends_at
        @metadata = metadata.to_h
      end

      def call
        return Result.failure(code: :not_found, errors: [ "subscription not found" ]) if subscription.blank?
        return Result.failure(code: :missing_transaction, errors: [ "provider transaction id is required" ]) if provider_transaction_id.blank?

        existing = find_existing_payment
        return Result.success(data: existing, code: :already_processed) if existing

        membership = subscription.membership
        mismatch = amount_mismatch
        return mismatch if mismatch

        outcome = nil
        extended = false

        PaymentEngine::Subscription.transaction do
          subscription.lock!
          membership.lock!

          existing = find_existing_payment
          if existing
            outcome = Result.success(data: existing, code: :already_processed)
            next
          end

          purchase = create_purchase(membership)
          payment = create_payment(purchase, membership)
          base, new_end = renewal_period(membership)

          if extend_membership?(membership, new_end)
            membership.update!(
              status: "active",
              expires_at: new_end,
              canceled_at: nil,
              metadata: membership.metadata.merge(metadata)
            )
            extended = true
          end

          update_subscription(base, new_end)
          purchase.update!(status: "completed", purchased_at: paid_at || PaymentEngine.current_time, membership: membership)
          @recorded_payment = payment
          outcome = Result.success(data: payment, code: :renewed)
        end

        publish_events(extended) if outcome&.success?
        outcome
      rescue ActiveRecord::RecordNotUnique
        existing = find_existing_payment
        return Result.success(data: existing, code: :already_processed) if existing

        Result.failure(code: :duplicate_transaction, errors: [ "renewal transaction was already recorded" ])
      rescue ActiveRecord::RecordInvalid => error
        Result.failure(code: :invalid_record, errors: error.record.errors.full_messages)
      end

      private

      attr_reader :subscription, :provider_transaction_id, :amount, :currency,
                  :paid_at, :period_starts_at, :period_ends_at, :metadata

      def find_existing_payment
        Payment.find_by(provider: subscription.provider, provider_transaction_id: provider_transaction_id)
      end

      def amount_mismatch
        if amount.present? && amount.to_i != subscription.effective_price
          return Result.failure(code: :amount_mismatch,
                                errors: [ "renewal amount does not match the subscription conditions" ])
        end
        if currency.present? && currency.to_s.upcase != subscription.effective_currency.to_s.upcase
          return Result.failure(code: :currency_mismatch,
                                errors: [ "renewal currency does not match the subscription conditions" ])
        end

        nil
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
          description: "Renewal of #{subscription.payment_option.name}",
          metadata: metadata.merge("subscription_id" => subscription.id, "renewal" => true)
        )
      end

      def create_payment(purchase, membership)
        purchase.payments.create!(
          provider: subscription.provider,
          membership: membership,
          amount: amount.present? ? amount.to_i : purchase.amount,
          currency: currency.presence || purchase.currency,
          status: "approved",
          provider_transaction_id: provider_transaction_id,
          paid_at: paid_at || PaymentEngine.current_time,
          metadata: metadata
        )
      end

      def renewal_period(membership)
        base = period_starts_at || subscription.current_period_ends_at || membership.expires_at || PaymentEngine.current_time
        new_end = period_ends_at.presence || subscription.duration_object.apply_to(base)
        [ base, new_end ]
      end

      def extend_membership?(membership, new_end)
        membership.expires_at.blank? || new_end > membership.expires_at
      end

      def update_subscription(base, new_end)
        subscription.update!(
          status: "active",
          current_period_starts_at: base,
          current_period_ends_at: new_end,
          next_billing_at: new_end,
          canceled_at: nil,
          cancel_at_period_end: false
        )
      end

      def publish_events(extended)
        payment = @recorded_payment
        Events.publish_after_commit(:payment_approved, payment: payment, purchase: payment&.purchase)
        Events.publish_after_commit(:subscription_renewed, subscription: subscription, payment: payment)
        Events.publish_after_commit(:membership_renewed, membership: subscription.membership) if extended
      end
    end
  end
end
