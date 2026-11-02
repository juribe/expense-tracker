module PaymentEngine
  module Subscriptions
    # Starts a renewal attempt through the provider. It never extends access by
    # itself: the period is extended only when the provider confirms the charge
    # (webhook -> RecordRenewal or Payments::Confirm).
    class Renew
      def self.call(subscription)
        new(subscription).call
      end

      def initialize(subscription)
        @subscription = subscription
      end

      def call
        return Result.failure(code: :not_found, errors: [ "subscription not found" ]) if subscription.blank?
        unless subscription.active?
          return Result.failure(code: :inactive_subscription, errors: [ "subscription is not active" ])
        end

        pending = pending_renewal
        return Result.success(data: renewal_data(pending), code: :renewal_pending) if pending

        adapter = PaymentEngine.provider(subscription.provider)
        unless adapter.supports?(:recurring_payments) && adapter.supports?(:payments)
          return Result.failure(code: :unsupported_operation,
                                errors: [ "#{adapter.name} cannot start recurring renewals" ])
        end

        purchase = nil
        payment = nil

        Purchase.transaction do
          purchase = Purchase.create!(
            owner: subscription.membership.owner,
            payment_option: subscription.payment_option,
            membership: subscription.membership,
            provider: adapter.name,
            status: "pending",
            price: subscription.effective_price,
            amount: subscription.effective_price,
            currency: subscription.effective_currency,
            billing_type: subscription.effective_billing_type,
            duration: subscription.duration_object.to_h,
            description: "Renewal of #{subscription.payment_option.name}",
            metadata: { "subscription_id" => subscription.id, "renewal" => true }
          )
          payment = purchase.payments.create!(
            provider: adapter.name,
            membership: subscription.membership,
            amount: purchase.amount,
            currency: purchase.currency,
            status: "pending"
          )
        end

        response = adapter.create_payment(purchase: purchase, payment: payment)
        response_data = response.data.to_h

        if response.success?
          payment.update!(
            provider_transaction_id: response_data[:provider_transaction_id].presence || payment.provider_transaction_id
          )
          Result.success(data: renewal_data(purchase), code: :renewal_started)
        else
          Purchase.transaction do
            purchase.update!(status: "failed")
            payment.update!(status: "rejected", failure_reason: response.error_message)
          end
          Result.failure(code: response.code || :provider_error, errors: response.errors,
                         data: renewal_data(purchase))
        end
      rescue ActiveRecord::RecordInvalid => error
        Result.failure(code: :invalid_record, errors: error.record.errors.full_messages)
      end

      private

      attr_reader :subscription

      def pending_renewal
        subscription.membership.purchases
          .where(status: %w[pending processing], payment_option: subscription.payment_option)
          .where("created_at >= ?", 1.day.ago)
          .order(:id)
          .first
      end

      def renewal_data(purchase)
        { subscription: subscription, purchase: purchase, payment: purchase.payments.order(:id).last }
      end
    end
  end
end
