# frozen_string_literal: true

module Reconciliation
  # "Dejar pendiente": records that the user reviewed the difference and
  # chose to defer. The row stays flagged (amber) instead of forcing a
  # resolution — a balance discrepancy is not necessarily an expense.
  class LeavePending
    class << self
      def call(user:, money_source:, period: Date.current.strftime("%Y-%m"))
        snapshot = ReconciliationSnapshot.upsert_for!(
          user: user,
          money_source: money_source,
          period: period,
          actual_balance: Calculator.reconcilable_balance(money_source),
          resolution: "left_pending"
        )
        Invalidate.call(user_id: user.id)
        snapshot
      end
    end
  end
end
