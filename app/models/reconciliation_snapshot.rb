# frozen_string_literal: true

# The "real" balance the user entered for a money source during one
# reconciliation period, and how that check was resolved (ok / difference /
# adjusted / left_pending). Scoped per period so each month starts unverified.
class ReconciliationSnapshot < ApplicationRecord
  RESOLUTIONS = %w[unverified ok difference adjusted left_pending].freeze

  belongs_to :user
  belongs_to :money_source

  validates :period, presence: true, format: { with: /\A\d{4}-\d{2}\z/ }
  validates :resolution, inclusion: { in: RESOLUTIONS }
  validates :actual_balance, numericality: true

  scope :for_period, ->(user, period) { where(user_id: user.id, period: period) }

  def self.upsert_for!(user:, money_source:, period:, actual_balance:, resolution:, checked_at: Time.current)
    record = find_or_initialize_by(user_id: user.id, money_source_id: money_source.id, period: period)
    record.assign_attributes(
      actual_balance: actual_balance,
      resolution: resolution,
      checked_at: checked_at
    )
    record.save!
    record
  end
end
