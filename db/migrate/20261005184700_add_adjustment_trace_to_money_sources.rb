# frozen_string_literal: true

# Audit trail for the manual balance adjustment ("Ajustar saldo") from the
# Día de Cuadre dashboard: the offset stays transaction-free, but the last
# adjustment records when it happened and an optional user note, and is shown
# + reversible on the money source page.
class AddAdjustmentTraceToMoneySources < ActiveRecord::Migration[8.0]
  def change
    add_column :money_sources, :balance_offset_note, :string
    add_column :money_sources, :balance_offset_at, :datetime
  end
end
