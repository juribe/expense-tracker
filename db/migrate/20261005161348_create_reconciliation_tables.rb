# frozen_string_literal: true

# "Día de Cuadre" reconciliation feature.
#
# reconciliation_states  — persisted per user + period, so the dashboard does
#                          not recompute pending payments / discrepancies on
#                          every page load. Data changes mark it stale; the
#                          next visit or explicit Refresh recalculates it.
# reconciliation_snapshots — last "real" balance the user entered per source
#                          and period, plus how that check was resolved.
# money_sources.balance_offset — persistent correction applied on "Ajustar
#                          saldo" (no transaction is created). Included in
#                          MoneySource#balance and BalanceSync.rebuild! sums
#                          so the adjustment survives recomputes.
class CreateReconciliationTables < ActiveRecord::Migration[8.0]
  def change
    create_table :reconciliation_states do |t|
      t.references :user, null: false, foreign_key: true
      t.string :period, null: false
      t.string :status, null: false, default: "pending"
      t.integer :pending_payments_count, null: false, default: 0
      t.integer :discrepancies_count, null: false, default: 0
      t.jsonb :snapshot, null: false, default: {}
      t.datetime :checked_at
      t.boolean :stale, null: false, default: true

      t.timestamps

      t.index [ :user_id, :period ], unique: true
    end

    create_table :reconciliation_snapshots do |t|
      t.references :user, null: false, foreign_key: true
      t.references :money_source, null: false, foreign_key: true
      t.string :period, null: false
      t.decimal :actual_balance, precision: 14, scale: 2, null: false, default: "0.0"
      t.string :resolution, null: false, default: "unverified"
      t.datetime :checked_at

      t.timestamps

      t.index [ :user_id, :money_source_id, :period ], unique: true
    end

    add_column :money_sources, :balance_offset, :decimal, precision: 14, scale: 2, null: false, default: "0.0"
  end
end
