# frozen_string_literal: true

module PaymentEngine
  class MembershipType < ApplicationRecord
    has_many :payment_options, dependent: :restrict_with_error
    has_many :memberships, dependent: :restrict_with_error

    validates :name, presence: true
    validates :code, presence: true, uniqueness: true

    scope :active, -> { where(status: "active") }

    def archived?; status == "archived"; end
  end
end
