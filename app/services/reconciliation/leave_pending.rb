# frozen_string_literal: true

module Reconciliation
  # "Dejar pendiente": records that the user reviewed the source and chose to
  # defer. The row stays pending instead of forcing a resolution — a balance
  # discrepancy is not necessarily an expense. The reviewed real balance is
  # not stored.
  class LeavePending
    class << self
      def call(user:, money_source:, period: Date.current.strftime("%Y-%m"))
        snapshot = ReconciliationSnapshot.upsert_for!(
          user: user,
          money_source: money_source,
          period: period,
          resolution: "left_pending"
        )
        Invalidate.call(user_id: user.id)
        snapshot
      end
    end
  end
end
