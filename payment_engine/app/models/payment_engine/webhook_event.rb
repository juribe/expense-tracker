# frozen_string_literal: true

module PaymentEngine
  class WebhookEvent < ApplicationRecord
    validates :provider_code, presence: true
    validates :status, inclusion: { in: %w[received processed failed] }

    def processed?; status == "processed"; end
    def failed?; status == "failed"; end
  end
end
