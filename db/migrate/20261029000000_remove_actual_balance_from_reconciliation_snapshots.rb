# frozen_string_literal: true

# The reconciliation row only needs to remember whether the source was
# reconciled in the cycle. The "real" balance and its calculated difference
# are transient values used inside the Conciliar modal; keeping them would
# compare the bank against an old, already-consumed figure.
class RemoveActualBalanceFromReconciliationSnapshots < ActiveRecord::Migration[8.1]
  def change
    remove_column :reconciliation_snapshots, :actual_balance, :decimal,
                  precision: 14, scale: 2, default: "0.0", null: false
  end
end
