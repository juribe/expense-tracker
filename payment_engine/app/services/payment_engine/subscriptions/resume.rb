# frozen_string_literal: true

module PaymentEngine
  module Subscriptions
    class Resume
      def self.call(subscription:, actor: nil, reason: nil)
        unless subscription.cancelled?
          return PaymentEngine::Result.new(success: false, errors: ["La suscripción no está cancelada"])
        end
        ActiveRecord::Base.transaction do
          subscription.update!(status: "active")
          AuditLog.create!(
            actor_type: actor&.class&.name || "System",
            actor_id: actor&.id,
            action: "subscription.resumed",
            auditable_type: subscription.class.name,
            auditable_id: subscription.id,
            reason: reason,
            changes: { status: "active" },
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
