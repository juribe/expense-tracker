module PaymentEngine
  module Subscriptions
    # Cancels a subscription immediately or at the end of the paid period.
    # Scheduling a cancellation never removes access before the period ends.
    # Canceling a renewal is not the same as refunding previous payments.
    class Cancel
      def self.call(subscription, immediately: false)
        new(subscription, immediately: immediately).call
      end

      def initialize(subscription, immediately: false)
        @subscription = subscription
        @immediately = immediately
      end

      def call
        return Result.failure(code: :not_found, errors: [ "subscription not found" ]) if subscription.blank?
        return Result.success(data: subscription, code: :already_canceled) if subscription.status == "canceled"
        if !immediately && subscription.cancel_at_period_end?
          return Result.success(data: subscription, code: :already_scheduled)
        end

        provider_result = request_provider_cancellation
        return provider_result if provider_result&.error?

        PaymentEngine::Subscription.transaction do
          subscription.lock!

          if immediately
            cancel_now!
          else
            subscription.update!(cancel_at_period_end: true, canceled_at: PaymentEngine.current_time)
          end
        end

        publish_events
        Result.success(data: subscription, code: immediately ? :canceled : :scheduled)
      end

      private

      attr_reader :subscription, :immediately

      def request_provider_cancellation
        return if subscription.provider_subscription_id.blank?

        adapter = PaymentEngine.provider(subscription.provider)
        unless adapter.supports?(:subscription_cancellation)
          return Result.failure(code: :unsupported_operation,
                                errors: [ "#{adapter.name} does not support subscription cancellation" ])
        end

        adapter.cancel_subscription(
          provider_subscription_id: subscription.provider_subscription_id,
          immediately: immediately
        )
      end

      def cancel_now!
        now = PaymentEngine.current_time
        subscription.update!(status: "canceled", canceled_at: now, cancel_at_period_end: false)

        membership = subscription.membership
        membership.lock!
        membership.update!(status: "canceled", canceled_at: now)
      end

      def publish_events
        Events.publish_after_commit(:subscription_canceled, subscription: subscription)
        return unless immediately

        Events.publish_after_commit(:membership_canceled, membership: subscription.membership)
      end
    end
  end
end
