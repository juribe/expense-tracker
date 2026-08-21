# frozen_string_literal: true

class CreateRecurringTransactionOccurrences < ActiveRecord::Migration[8.0]
  def change
    create_table :recurring_transaction_occurrences do |t|
      t.references :recurring_transaction, null: false, foreign_key: true

      # Polymorphic reference to the generated transaction (Income / Expense)
      t.string :transaction_type, null: false
      t.integer :transaction_id, null: false

      t.date :transaction_date, null: false

      # Example: "2026-08"
      t.string :period, null: false

      t.timestamps
    end

    add_index :recurring_transaction_occurrences, [:recurring_transaction_id, :period],
              unique: true, name: 'index_recurring_transactions_on_period'
    add_index :recurring_transaction_occurrences, [:transaction_type, :transaction_id],
              name: 'index_recurring_transaction_occurrences_on_transaction'
  end
end
