# frozen_string_literal: true

module PaymentEngine
  # Access questions for a user, resolved from the commercial settings and the
  # memberships owned by that user id. Answers are memoized in Rails.cache for
  # an hour so repeated requests don't hit the DB.
  #
  # Example: PaymentEngine::UserAccess.new(user.id).access_premium?
  class UserAccess
    DEFAULT_OWNER_TYPE = "User"

    def initialize(user_id, owner_type: DEFAULT_OWNER_TYPE)
      @user_id = user_id
      @owner_type = owner_type
    end

    def need_membership?
      Rails.cache.fetch(cache_key(:need_membership), expires_in: 1.hour) do
        PaymentEngine::Configuration.paid_access_required? && !memberships.exists?
      end
    end

    def free_membership_used?
      Rails.cache.fetch(cache_key(:free_membership_used), expires_in: 1.hour) do
        memberships.where(source: "trial").exists?
      end
    end

    def access_premium?
      Rails.cache.fetch(cache_key(:access_premium), expires_in: 1.hour) do
        !PaymentEngine::Configuration.paid_access_required? ||
          active_trial? ||
          active_paid_membership?
      end
    end

    def current_membership
      memberships.order(expires_at: :desc).first
    end

    def membership_expiring_within_days?(days)
      membership = current_membership
      return false unless membership&.active? && membership.expires_at.present?

      days_left = (membership.expires_at.to_date - Date.current).to_i
      days_left.between?(0, days)
    end

    private

    attr_reader :user_id, :owner_type

    def memberships
      PaymentEngine::Membership.where(owner_type: owner_type, owner_id: user_id)
    end

    def cache_key(question)
      [ "payment_engine_user_access", owner_type, user_id, question, membership_cache_version ].compact_blank.join(":")
    end

    def membership_cache_version
      [ PaymentEngine::Setting.current.updated_at&.to_s, memberships.maximum(:updated_at)&.to_s ].join("-")
    end

    def active_memberships
      memberships
        .where(status: "active")
        .where("expires_at IS NULL OR expires_at >= ?", Time.current)
    end

    def active_trial?
      active_memberships.where(source: "trial").exists?
    end

    def active_paid_membership?
      active_memberships.where("source IS NULL OR source <> ?", "trial").exists?
    end
  end
end
