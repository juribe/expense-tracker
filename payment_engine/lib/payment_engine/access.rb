# frozen_string_literal: true

module PaymentEngine
  module Access
    def self.granted?(owner)
      return false unless owner
      PaymentEngine::Membership.where(owner: owner, status: "active")
        .where("expires_at IS NULL OR expires_at >= ?", Time.current).exists?
    end
  end
end
