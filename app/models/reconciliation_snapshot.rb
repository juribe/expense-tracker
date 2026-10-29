# frozen_string_literal: true

# Whether a money source was reconciled during one reconciliation period.
# The "real" balance the user enters in the Conciliar modal is transient: it
# only drives the one-off difference/adjustment and is never remembered, so
# the next reconciliation starts from the app balance again. Scoped per
# period so each cycle starts unverified.
class ReconciliationSnapshot < ApplicationRecord
  RESOLUTIONS = %w[unverified ok difference adjusted left_pending].freeze

  belongs_to :user
  belongs_to :money_source

  # Calendar month ("YYYY-MM") or pay cycle start date ("YYYY-MM-DD"); the
  # dashboard looks snapshots up with whatever key PayCycle.period_for returns.
  validates :period, presence: true, format: { with: /\A\d{4}-\d{2}(-\d{2})?\z/ }
  validates :resolution, inclusion: { in: RESOLUTIONS }

  scope :for_period, ->(user, period) { where(user_id: user.id, period: period) }

  def self.upsert_for!(user:, money_source:, period:, resolution:, checked_at: Time.current)
    record = find_or_initialize_by(user_id: user.id, money_source_id: money_source.id, period: period)
    record.assign_attributes(resolution: resolution, checked_at: checked_at)
    record.save!
    record
  end
end
