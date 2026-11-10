module PaymentEngine
  module Subscriptions
    # Applies a cancellation reported by the provider. Cancellations at period
    # end keep access until the paid period finishes; immediate cancellations
    # revoke access now. The provider is not called again.
    class ApplyProviderCancellation
      def self.call(subscription:, immediately: false)
        new(subscription: subscription, immediately: immediately).call
      end

      def initialize(subscription:, immediately: false)
        @subscription = subscription
        @immediately = immediately
      end

      def call
        return Result.failure(code: :not_found, errors: [ "subscription not found" ]) if subscription.blank?
        return Result.success(data: subscription, code: :already_canceled) if subscription.status == "canceled"

        code = nil

        PaymentEngine::Subscription.transaction do
          subscription.lock!
          now = PaymentEngine.current_time

          if immediately || subscription.current_period_ends_at.blank? || subscription.current_period_ends_at <= now
            subscription.update!(status: "canceled", canceled_at: now, cancel_at_period_end: false)
            membership = subscription.membership
            membership.lock!
            membership.update!(status: "canceled", canceled_at: now)
            code = :canceled
          else
            subscription.update!(cancel_at_period_end: true, canceled_at: now)
            code = :scheduled
          end
        end

        if code == :canceled
          Events.publish_after_commit(:subscription_canceled, subscription: subscription)
          Events.publish_after_commit(:membership_canceled, membership: subscription.membership)
        end

        Result.success(data: subscription, code: code)
      end

      private

      attr_reader :subscription, :immediately
    end
  end
end
