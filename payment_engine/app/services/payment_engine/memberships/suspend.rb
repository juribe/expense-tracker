# frozen_string_literal: true

module PaymentEngine
  module Memberships
    class Suspend
      def self.call(membership:, actor: nil, reason: nil)
        unless membership.active?
          return PaymentEngine::Result.new(success: false, errors: ["La membresía no está activa"])
        end
        ActiveRecord::Base.transaction do
          membership.update!(status: "suspended")
          AuditLog.create!(
            actor_type: actor&.class&.name || "System",
            actor_id: actor&.id,
            action: "membership.suspended",
            auditable_type: membership.class.name,
            auditable_id: membership.id,
            reason: reason,
            changes: { status: { from: "active", to: "suspended" } },
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
