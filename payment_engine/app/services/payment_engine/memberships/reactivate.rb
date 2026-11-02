# frozen_string_literal: true

module PaymentEngine
  module Memberships
    class Reactivate
      def self.call(membership:, actor: nil, reason: nil)
        unless membership.suspended?
          return PaymentEngine::Result.new(success: false, errors: ["La membresía no está suspendida"])
        end
        ActiveRecord::Base.transaction do
          membership.update!(status: "active")
          AuditLog.create!(
            actor_type: actor&.class&.name || "System",
            actor_id: actor&.id,
            action: "membership.reactivated",
            auditable_type: membership.class.name,
            auditable_id: membership.id,
            reason: reason,
            changes: { status: { from: "suspended", to: "active" } },
            metadata: {}
          )
        end
        PaymentEngine::Result.new(success: true, record: membership)
      rescue StandardError => e
        PaymentEngine::Result.new(success: false, errors: [e.message])
      end
    end
  end
end
