# frozen_string_literal: true

module PaymentEngine
  class Provider < ApplicationRecord
    validates :code, presence: true, uniqueness: true
    validates :name, presence: true
    validates :environment, inclusion: { in: %w[sandbox production] }

    scope :active, -> { where(active: true) }

    def configured?
      credentials.present? && credentials.any?
    end
  end
end
