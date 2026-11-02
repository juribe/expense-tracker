# frozen_string_literal: true

module PaymentEngine
  class Subscription < ApplicationRecord
    belongs_to :payment_option, optional: true
    belongs_to :owner, polymorphic: true

    validates :status, inclusion: { in: %w[active cancelled paused expired] }

    def active?; status == "active"; end
    def cancelled?; status == "cancelled"; end
  end
end
