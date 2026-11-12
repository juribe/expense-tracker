# frozen_string_literal: true

# PremiumIdentities::UserAccessExtension
# Extends PaymentEngine::UserAccess with the membership behind the account
# email identity. A returning identity keeps free access and cannot obtain
# premium again.
module PremiumIdentities
  module UserAccessExtension
    def need_membership?
      Rails.cache.fetch(cache_key(:need_membership), expires_in: 1.hour) do
        super && !identity_membership_used?
      end
    end

    def free_membership_used?
      Rails.cache.fetch(cache_key(:free_membership_used), expires_in: 1.hour) do
        super || identity_membership_used?
      end
    end

    def current_membership
      super || identity_membership
    end

    def renewal_prompt?
      super || (identity_membership_used? && !access_premium?)
    end

    private

    def identity_membership
      return nil unless resolvable_user? && identity_membership_used?

      MembershipHistory.membership_for(User.find_by(id: user_id))
    end

    def identity_membership_used?
      return false unless resolvable_user?

      MembershipHistory.used_by?(User.find_by(id: user_id))
    end

    def membership_cache_version
      [ super, identity_cache_version ].compact_blank.join("-")
    end

    def identity_cache_version
      return "" unless resolvable_user?

      identity = MembershipHistory.identity_for(User.find_by(id: user_id))
      return "" unless identity

      [ identity.updated_at.utc.iso8601(6), identity.released_at&.utc&.iso8601(6) ].compact_blank.join("-")
    end

    def resolvable_user?
      owner_type == PaymentEngine::UserAccess::DEFAULT_OWNER_TYPE
    end
  end
end
