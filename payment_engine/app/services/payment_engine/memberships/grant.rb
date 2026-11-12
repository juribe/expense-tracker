# frozen_string_literal: true

module PaymentEngine
  module Memberships
    class Grant
      def self.call(owner:, membership_type:, starts_at: nil, expires_at: nil, source: "manual", actor: nil, reason: nil, purchase: nil, subscription: nil)
        starts_at ||= Time.current
        membership = Membership.new(
          owner: owner,
          membership_type: membership_type,
          status: "active",
          starts_at: starts_at,
          expires_at: expires_at,
          source: source,
          purchase: purchase,
          subscription: subscription
        )
        ActiveRecord::Base.transaction do
          membership.save!
          PremiumIdentities::Protection.claim_membership_owner!(membership)
          AuditLog.create!(
            actor_type: actor&.class&.name || "System",
            actor_id: actor&.id,
            action: "membership.granted",
            auditable_type: membership.class.name,
            auditable_id: membership.id,
            reason: reason,
            changes: { status: "active", starts_at: starts_at, expires_at: expires_at },
            metadata: { owner_type: owner.class.name, owner_id: owner.id }
          )
        end
        PaymentEngine::Result.new(success: true, record: membership)
      rescue ActiveRecord::RecordInvalid => e
        PaymentEngine::Result.new(success: false, errors: e.record.errors.full_messages)
      rescue PremiumIdentities::Protection::Conflict => e
        PaymentEngine::Result.new(success: false, errors: [ e.message ])
      rescue StandardError => e
        PaymentEngine::Result.new(success: false, errors: [ e.message ])
      end
    end
  end
end
