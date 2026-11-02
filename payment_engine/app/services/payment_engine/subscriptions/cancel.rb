# frozen_string_literal: true

module PaymentEngine
  module Subscriptions
    class Cancel
      def self.call(subscription:, actor: nil, reason: nil, cancel_at_period_end: true)
        ActiveRecord::Base.transaction do
          subscription.update!(status: "cancelled")
          AuditLog.create!(
            actor_type: actor&.class&.name || "System",
            actor_id: actor&.id,
            action: "subscription.cancelled",
            auditable_type: subscription.class.name,
            auditable_id: subscription.id,
            reason: reason,
            changes: { status: "cancelled", cancel_at_period_end: cancel_at_period_end },
            metadata: {}
          )
        end
        PaymentEngine::Result.new(success: true, record: subscription)
      rescue StandardError => e
        PaymentEngine::Result.new(success: false, errors: [e.message])
      end
    end
  end
end
