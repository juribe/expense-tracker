# frozen_string_literal: true

module PaymentEngine
  module Memberships
    class StartFreeTrial
      def self.call(owner:, membership_type: nil, actor: nil)
        settings = PaymentEngine::Setting.current
        unless settings.free_trial_enabled
          return PaymentEngine::Result.new(success: false, errors: ["El free trial está desactivado"])
        end

        membership_type ||= PaymentEngine::MembershipType.active.first
        return PaymentEngine::Result.new(success: false, errors: ["No hay tipo de membresía"]) unless membership_type

        # eligibility: no prior trial
        if settings.free_trial_once_per_user
          existing_trial = PaymentEngine::Membership.where(owner: owner, source: "trial").exists?
          if existing_trial
            return PaymentEngine::Result.new(success: false, errors: ["El usuario ya utilizó su prueba gratuita"])
          end
        end

        # no incompatible active membership
        active = PaymentEngine::Membership.where(owner: owner, status: "active").where("expires_at IS NULL OR expires_at >= ?", Time.current).exists?
        if active
          return PaymentEngine::Result.new(success: false, errors: ["El usuario ya tiene una membresía activa"])
        end

        duration = settings.free_trial_duration_days.days
        starts_at = Time.current
        expires_at = starts_at + duration

        membership = nil
        ActiveRecord::Base.transaction do
          membership = PaymentEngine::Membership.create!(
            owner: owner,
            membership_type: membership_type,
            status: "active",
            source: "trial",
            starts_at: starts_at,
            expires_at: expires_at
          )
          owner.update!(requires_membership: false) if owner.respond_to?(:requires_membership=)
          PaymentEngine::AuditLog.create!(
            actor_type: actor&.class&.name || owner.class.name,
            actor_id: actor&.id || owner.id,
            action: "membership.trial_started",
            auditable_type: membership.class.name,
            auditable_id: membership.id,
            reason: "free_trial",
            changes: { source: "trial", duration_days: settings.free_trial_duration_days },
            metadata: { owner_type: owner.class.name, owner_id: owner.id }
          )
        end
        PaymentEngine::Result.new(success: true, record: membership)
      rescue ActiveRecord::RecordNotUnique
        PaymentEngine::Result.new(success: false, errors: ["El usuario ya utilizó su prueba gratuita"])
      rescue StandardError => e
        PaymentEngine::Result.new(success: false, errors: [e.message])
      end
    end
  end
end
