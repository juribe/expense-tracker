# frozen_string_literal: true

# PremiumIdentities::MembershipHistory
# Exposes the membership behind an account email identity. A new account whose
# email identity already used premium keeps the free plan, but cannot obtain
# premium again.
#
# Example: PremiumIdentities::MembershipHistory.used_by?(user)
module PremiumIdentities
  class MembershipHistory
    IDENTITY_TYPE = "account_email"

    class << self
      def identity_for(user)
        return nil unless user.is_a?(User)

        ::PremiumIdentity.find_by(
          identity_type: IDENTITY_TYPE,
          fingerprint: PremiumIdentities::Fingerprint.call(
            identity_type: IDENTITY_TYPE,
            value: user.email
          )
        )
      end

      def used_by?(user)
        identity = identity_for(user)
        return false unless identity
        return false if identity.released?

        identity.payment_engine_membership_id.present? && !identity.owned_by?(user)
      end

      def membership_for(user)
        identity = identity_for(user)
        return nil if identity.nil? || identity.released? || identity.owned_by?(user)

        identity.membership
      end
    end
  end
end
