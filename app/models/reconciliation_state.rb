# frozen_string_literal: true

# Persisted "Día de Cuadre" state for one user and period. The period key is
# the calendar month ("YYYY-MM", the historical shape) or — for users with a
# configured pay schedule — the pay cycle's start date ("YYYY-MM-DD").
#
# The dashboard reads this row instead of recomputing pending payments and
# balance discrepancies on every page load. Reconciliation::Invalidate marks
# it stale whenever relevant financial data changes; Reconciliation::State
# then recalculates on the next visit or explicit Refresh.
class ReconciliationState < ApplicationRecord
  STATUSES = %w[pending warning reconciled].freeze

  belongs_to :user

  validates :period, presence: true, format: { with: /\A\d{4}-\d{2}(-\d{2})?\z/ }
  validates :status, inclusion: { in: STATUSES }

  scope :for_user, ->(user) { where(user_id: user.id) }

  def self.for_period(user, period)
    for_user(user).find_by(period: period)
  end

  def reconciled?
    status == "reconciled"
  end

  def stale?
    stale || checked_at.nil?
  end
end
