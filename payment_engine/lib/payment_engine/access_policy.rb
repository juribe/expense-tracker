# frozen_string_literal: true

module PaymentEngine
  module AccessPolicy
    def self.premium_access?(owner)
      settings = PaymentEngine::Setting.current rescue nil
      required = settings&.paid_access_required != false
      return true unless required

      PaymentEngine::Membership.where(owner: owner, status: "active")
        .where("expires_at IS NULL OR expires_at >= ?", Time.current).exists?
    end

    def self.can_start_trial?(owner)
      settings = PaymentEngine::Setting.current rescue nil
      return false unless settings&.free_trial_enabled
      if settings&.free_trial_once_per_user != false
        return false if PaymentEngine::Membership.where(owner: owner, source: "trial").exists?
      end
      return false unless premium_identity_available?(owner)
      # no incompatible active membership
      active = PaymentEngine::Membership.where(owner: owner, status: "active").where("expires_at IS NULL OR expires_at >= ?", Time.current).exists?
      return false if active
      true
    end

    # The permanent email identity applies even when the trial-once setting is
    # disabled: an identity used by another account is never reusable.
    def self.premium_identity_available?(owner)
      return true unless owner.respond_to?(:email)

      ::PremiumIdentities::Protection.available?(
        identity_type: "account_email",
        value: owner.email,
        user: owner
      )
    end
  end
end
