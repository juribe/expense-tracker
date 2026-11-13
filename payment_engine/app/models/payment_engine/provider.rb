# frozen_string_literal: true

module PaymentEngine
  class Provider < ApplicationRecord
    attribute :credentials, :json
    attribute :settings, :json

    encrypts :credentials
    encrypts :settings

    validates :code, presence: true, uniqueness: true
    validates :name, presence: true
    validates :environment, inclusion: { in: %w[sandbox production] }

    scope :active, -> { where(active: true) }

    # Adapters are memoized per process with the settings loaded at first use,
    # so a credential change must invalidate them or the old secret keeps
    # verifying webhooks until the process restarts.
    after_commit :reset_provider_instances

    def configured?
      credentials.present? && credentials.any?
    end

    private

    def reset_provider_instances
      PaymentEngine.reset_providers!
    end
  end
end
