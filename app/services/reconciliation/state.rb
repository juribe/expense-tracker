# frozen_string_literal: true

module Reconciliation
  # Loads (and recalculates when stale) the persisted dashboard state.
  #
  #   Reconciliation::State.call(user)                     # auto: recompute if stale/missing
  #   Reconciliation::State.refresh!(user)                 # explicit Refresh button
  class State
    def self.call(user, period: Date.current.strftime("%Y-%m"))
      state = ReconciliationState.for_period(user, period)
      return state if state && !state.stale? && current_snapshot?(state)

      refresh!(user, period: period)
    end

    def self.refresh!(user, period: Date.current.strftime("%Y-%m"))
      result = Calculator.call(user: user, period: period)
      state = ReconciliationState.find_or_initialize_by(user_id: user.id, period: period)
      state.assign_attributes(
        status: derive_status(result),
        pending_payments_count: result.pending_payments_count,
        discrepancies_count: result.discrepancies_count,
        unverified_count: result.unverified_count,
        snapshot: {
          version: Calculator::SNAPSHOT_VERSION,
          pending_payments: result.pending_payments,
          balances: result.balances
        },
        checked_at: Time.current,
        stale: false
      )
      state.save!
      state
    end

    # Payload built with a different snapshot shape (schema drift, old flush)
    # must be transparently rebuilt: views read keys it may not contain.
    def self.current_snapshot?(state)
      state.snapshot["version"] == Calculator::SNAPSHOT_VERSION
    end

    # "Todo cuadrado" means everything was actually checked: recurring
    # payments assigned, every difference resolved, and no source left
    # unverified in the period.
    def self.derive_status(result)
      return "pending" if result.pending_payments_count.positive?
      return "pending" if result.unverified_count.positive?
      return "warning" if result.discrepancies_count.positive?

      "reconciled"
    end
  end
end
