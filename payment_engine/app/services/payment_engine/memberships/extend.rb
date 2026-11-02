# frozen_string_literal: true

module PaymentEngine
  module Memberships
    class Extend
      def self.call(membership:, new_expires_at: nil, duration: nil, actor: nil, reason: nil)
        base = membership.expires_at || Time.current
        expires = new_expires_at
        if expires.nil? && duration
          expires = base + duration
        end
        return PaymentEngine::Result.new(success: false, errors: ["Fecha de expiración requerida"]) if expires.nil?

        old = membership.expires_at
        ActiveRecord::Base.transaction do
          membership.update!(expires_at: expires)
          AuditLog.create!(
            actor_type: actor&.class&.name || "System",
            actor_id: actor&.id,
            action: "membership.extended",
            auditable_type: membership.class.name,
            auditable_id: membership.id,
            reason: reason,
            changes: { expires_at: { from: old, to: expires } },
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
