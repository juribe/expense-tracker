# frozen_string_literal: true

module PaymentEngine
  class Membership < ApplicationRecord
    belongs_to :membership_type
    belongs_to :purchase, optional: true
    belongs_to :subscription, optional: true
    belongs_to :owner, polymorphic: true

    validates :status, inclusion: { in: %w[active suspended cancelled expired] }

    scope :active, -> { where(status: "active") }

    def active?; status == "active"; end
    def suspended?; status == "suspended"; end
    def cancelled?; status == "cancelled"; end
    def expired?; status == "expired"; end

    def expired_by_date?
      expires_at.present? && expires_at < Time.current
    end

    def access_granted?
      active? && !expired_by_date?
    end
  end
end
