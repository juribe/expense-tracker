# frozen_string_literal: true

# PremiumIdentities::Protection
# Central claim/check service for identifiers that grant premium access.
# A row is created on first use and is only reusable by the same account,
# unless an administrator explicitly releases it.
#
# Example: PremiumIdentities::Protection.claim!(
#   identity_type: "gmail", value: "user@gmail.com", user: user, membership: membership
# )
module PremiumIdentities
  class Protection
    class Conflict < StandardError; end

    CONFLICT_MESSAGE = "Esta identidad ya está asociada a otra cuenta."

    class << self
      def claim!(identity_type:, value:, user:, membership: nil)
        new(identity_type: identity_type, value: value, user: user, membership: membership).claim!
      end

      def available?(identity_type:, value:, user:)
        new(identity_type: identity_type, value: value, user: user).available?
      end

      # Records the account email behind a membership. Used by trial and paid
      # grants so every premium account leaves a permanent identity.
      def claim_membership_owner!(membership)
        owner = membership.owner
        return nil unless owner.is_a?(User)

        claim!(
          identity_type: "account_email",
          value: owner.email,
          user: owner,
          membership: membership
        )
      end
    end

    def initialize(identity_type:, value:, user:, membership: nil)
      @identity_type = identity_type.to_s
      @value = value
      @user = user
      @membership = membership
    end

    def claim!
      return nil if fingerprint.blank?

      identity = PremiumIdentity.find_by(fingerprint: fingerprint)
      return register_identity! unless identity

      verify_ownership!(identity)
      refresh_identity!(identity)
    end

    def available?
      return true if fingerprint.blank?

      identity = PremiumIdentity.find_by(fingerprint: fingerprint)
      identity.nil? || identity.available_to?(@user)
    end

    private

    def fingerprint
      @fingerprint ||= PremiumIdentities::Fingerprint.call(identity_type: @identity_type, value: @value)
    end

    def register_identity!
      PremiumIdentity.transaction(requires_new: true) do
        PremiumIdentity.create!(
          identity_type: @identity_type,
          fingerprint: fingerprint,
          first_user: @user,
          membership: @membership,
          first_used_at: Time.current
        )
      end
    rescue ActiveRecord::RecordNotUnique
      identity = PremiumIdentity.find_by(fingerprint: fingerprint)
      raise Conflict, CONFLICT_MESSAGE unless identity

      verify_ownership!(identity)
      refresh_identity!(identity)
    end

    def verify_ownership!(identity)
      return if identity.released?
      raise Conflict, CONFLICT_MESSAGE unless identity.owned_by?(@user)
    end

    def refresh_identity!(identity)
      if identity.released?
        reassign_released_identity!(identity)
      else
        link_membership!(identity)
      end
      identity
    end

    def reassign_released_identity!(identity)
      identity.with_lock do
        if identity.released?
          identity.update!(reassignment_attributes)
        else
          verify_ownership!(identity)
          link_membership!(identity)
        end
      end
    end

    def link_membership!(identity)
      return unless @membership
      return if identity.payment_engine_membership_id.present?

      identity.update!(payment_engine_membership_id: @membership.id)
    end

    def reassignment_attributes
      {
        first_user: @user,
        first_used_at: Time.current,
        payment_engine_membership_id: @membership&.id,
        released_at: nil,
        released_by_user: nil,
        release_reason: nil
      }
    end
  end
end
