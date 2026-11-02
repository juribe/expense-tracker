module PaymentEngine
  module Memberships
    # Moves a membership whose paid period has ended to expired. Idempotent:
    # calling it repeatedly has no additional effect and publishes one event.
    class Expire
      def self.call(membership)
        new(membership).call
      end

      def initialize(membership)
        @membership = membership
      end

      def call
        return Result.failure(code: :not_found, errors: [ "membership not found" ]) if membership.blank?

        expired = false

        Membership.transaction do
          membership.lock!

          if expirable?
            membership.update!(status: "expired")
            expired = true
          end
        end

        Events.publish_after_commit(:membership_expired, membership: membership) if expired
        Result.success(data: membership, code: expired ? :expired : :unchanged)
      end

      private

      attr_reader :membership

      def expirable?
        Membership::ACCESS_STATUSES.include?(membership.status) &&
          membership.expires_at.present? &&
          membership.expires_at <= PaymentEngine.current_time
      end
    end
  end
end
