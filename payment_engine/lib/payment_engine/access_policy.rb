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
      # no incompatible active membership
      active = PaymentEngine::Membership.where(owner: owner, status: "active").where("expires_at IS NULL OR expires_at >= ?", Time.current).exists?
      return false if active
      true
    end
  end
end
