# frozen_string_literal: true

module PaymentEngine
  class Purchase < ApplicationRecord
    belongs_to :payment_option, optional: true
    belongs_to :owner, polymorphic: true
    belongs_to :payment, optional: true, class_name: "PaymentEngine::Payment", foreign_key: :payment_id
    belongs_to :membership, optional: true, class_name: "PaymentEngine::Membership", foreign_key: :membership_id
    belongs_to :subscription, optional: true, class_name: "PaymentEngine::Subscription", foreign_key: :subscription_id

    validates :code, presence: true, uniqueness: true
    validates :status, inclusion: { in: %w[pending paid failed cancelled refunded] }

    before_validation :ensure_code

    def ensure_code
      self.code ||= "PUR-#{SecureRandom.hex(8).upcase}"
    end
  end
end
