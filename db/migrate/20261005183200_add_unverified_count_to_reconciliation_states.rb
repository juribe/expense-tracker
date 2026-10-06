# frozen_string_literal: true

# "Día de Cuadre" now also counts sources that have never been verified in
# the period ("sin conciliar"), so the status strip reflects missing
# reconciliations and "Todo cuadrado" really means every source was checked.
class AddUnverifiedCountToReconciliationStates < ActiveRecord::Migration[8.0]
  def change
    add_column :reconciliation_states, :unverified_count, :integer, null: false, default: 0
  end
end
