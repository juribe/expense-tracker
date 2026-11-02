module PaymentEngine
  module Jobs
    # Daily maintenance. Idempotent: running it repeatedly produces no
    # additional state changes or duplicate events.
    #
    # Order matters: scheduled cancellations are finalized before generic
    # expiration so a canceled membership ends as canceled, not expired.
    class ExpireMembershipsJob < ApplicationJob
      def perform
        canceled_subscriptions = finalize_scheduled_cancellations
        expired_memberships = expire_memberships
        expired_subscriptions = expire_subscriptions

        { subscriptions_canceled: canceled_subscriptions,
          memberships_expired: expired_memberships,
          subscriptions_expired: expired_subscriptions }
      end

      private

      def finalize_scheduled_cancellations
        count = 0
        now = PaymentEngine.current_time

        Subscription.renewable.where(cancel_at_period_end: true)
          .where("current_period_ends_at IS NOT NULL AND current_period_ends_at <= ?", now)
          .find_each do |subscription|
            membership_canceled = false
            subscription.with_lock do
              subscription.update!(status: "canceled", canceled_at: subscription.canceled_at || now,
                                   cancel_at_period_end: false)
              membership = subscription.membership
              membership.lock!
              if membership.expires_at.nil? || membership.expires_at <= now
                membership.update!(status: "canceled", canceled_at: membership.canceled_at || now)
                membership_canceled = true
              end
            end
            Events.publish_after_commit(:subscription_canceled, subscription: subscription)
            if membership_canceled
              Events.publish_after_commit(:membership_canceled, membership: subscription.membership)
            end
            count += 1
          end

        count
      end

      def expire_memberships
        count = 0

        Membership.expired_by_date.find_each do |membership|
          result = Memberships::Expire.call(membership)
          count += 1 if result.success? && result.code == :expired
        end

        count
      end

      def expire_subscriptions
        count = 0
        now = PaymentEngine.current_time

        Subscription.renewable.where("current_period_ends_at IS NOT NULL AND current_period_ends_at <= ?", now)
          .find_each do |subscription|
            subscription.with_lock do
              subscription.update!(status: "expired")
            end
            count += 1
          end

        count
      end
    end
  end
end
