# frozen_string_literal: true

# PremiumIdentities::Release
# The only supported way to free a historical premium identity. The row is kept
# and the operation is recorded in the payment engine audit log.
#
# Example: PremiumIdentities::Release.call(identity: identity, actor: admin, reason: "Support request")
module PremiumIdentities
  class Release
    REASON_REQUIRED = "El motivo de la liberación es obligatorio."
    ALREADY_RELEASED = "La identidad ya fue liberada."

    class << self
      def call(identity:, actor: nil, reason: nil)
        new(identity: identity, actor: actor, reason: reason).call
      end
    end

    def initialize(identity:, actor:, reason:)
      @identity = identity
      @actor = actor
      @reason = reason.to_s.strip
    end

    def call
      return ServiceResult.error([ REASON_REQUIRED ]) if @reason.blank?

      @identity.with_lock do
        return ServiceResult.error([ ALREADY_RELEASED ]) if @identity.released?

        released_at = Time.current
        @identity.update!(
          released_at: released_at,
          released_by_user: @actor,
          release_reason: @reason
        )
        record_audit(released_at)
      end
      ServiceResult.success(@identity)
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.error(error.record.errors.full_messages)
    end

    private

    def record_audit(released_at)
      PaymentEngine::AuditLog.create!(
        actor_type: @actor&.class&.name || "System",
        actor_id: @actor&.id,
        action: "premium_identity.released",
        auditable_type: @identity.class.name,
        auditable_id: @identity.id,
        reason: @reason,
        changes: { released_at: released_at },
        metadata: {
          identity_type: @identity.identity_type,
          first_user_id: @identity.first_user_id,
          membership_id: @identity.payment_engine_membership_id
        }
      )
    end
  end
end
