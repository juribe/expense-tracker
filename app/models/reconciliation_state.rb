# frozen_string_literal: true

# Persisted "Día de Balance" state for one user and period. The period key is
# the calendar month ("YYYY-MM", the historical shape) or — for users with a
# configured pay schedule — the pay cycle's start date ("YYYY-MM-DD").
#
# The dashboard reads this row instead of recomputing pending payments and
# balance discrepancies on every page load. Reconciliation::Invalidate marks
# it stale whenever relevant financial data changes; Reconciliation::State
# then recalculates on the next visit or explicit Refresh.
#
# Presentation helpers: account_balances/debt_balances split the snapshot for
# the two list sections; progress counts only sources marked "ok".
class ReconciliationState < ApplicationRecord
  STATUSES = %w[pending warning reconciled].freeze
  DEBT_KINDS = %w[credit_card loan].freeze

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

  def pending_payments
    snapshot["pending_payments"] || []
  end

  def balances
    snapshot["balances"] || []
  end

  def account_balances
    balances.reject { |row| debt_kind?(row["kind"]) }
  end

  def debt_balances
    balances.select { |row| debt_kind?(row["kind"]) }
  end

  def verified_sources_count
    balances.count { |row| row["status"] == "ok" }
  end

  def total_sources_count
    balances.size
  end

  def progress_percentage
    return 0 if total_sources_count.zero?

    (verified_sources_count.to_f / total_sources_count * 100).round
  end

  def unverified_accounts_count
    account_balances.count { |row| row["status"] != "ok" }
  end

  def unverified_debts_count
    debt_balances.count { |row| row["status"] != "ok" }
  end

  private

  def debt_kind?(kind)
    DEBT_KINDS.include?(kind)
  end
end
