# frozen_string_literal: true

module PaymentEngine
  class Membership < ApplicationRecord
    belongs_to :membership_type, counter_cache: true
    belongs_to :purchase, optional: true
    belongs_to :subscription, optional: true
    belongs_to :owner, polymorphic: true

    validates :status, inclusion: { in: %w[active suspended cancelled expired] }
    validate :single_trial_per_owner, if: :trial?

    scope :active, -> { where(status: "active") }

    def trial?; source == "trial"; end
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

    private

    def single_trial_per_owner
      return if owner_type.blank? || owner_id.blank?

      existing_trials = self.class.where(owner_type: owner_type, owner_id: owner_id, source: "trial")
      existing_trials = existing_trials.where.not(id: id) if persisted?
      return unless existing_trials.exists?

      errors.add(:base, "La prueba gratuita ya fue utilizada por este usuario")
    end
  end
end
