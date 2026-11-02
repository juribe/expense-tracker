# frozen_string_literal: true

module PaymentEngine
  class Payment < ApplicationRecord
    belongs_to :purchase, optional: true, class_name: "PaymentEngine::Purchase", foreign_key: :purchase_id

    validates :status, inclusion: { in: %w[pending succeeded failed refunded] }
    validates :amount, numericality: { greater_than_or_equal_to: 0 }
  end
end
