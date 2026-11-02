# frozen_string_literal: true

module PaymentEngine
  module Memberships
    class Cancel
      def self.call(membership:, actor: nil, reason: nil)
        ActiveRecord::Base.transaction do
          membership.update!(status: "cancelled")
          AuditLog.create!(
            actor_type: actor&.class&.name || "System",
            actor_id: actor&.id,
            action: "membership.cancelled",
            auditable_type: membership.class.name,
            auditable_id: membership.id,
            reason: reason,
            changes: { status: "cancelled" },
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
