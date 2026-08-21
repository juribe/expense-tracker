# frozen_string_literal: true

class CreateRecurringTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :recurring_transactions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true

      # income / expense
      t.string :transaction_type, null: false

      t.decimal :amount, precision: 10, scale: 2, null: false

      t.string :description

      t.string :frequency, default: "monthly", null: false

      t.integer :payment_day

      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :recurring_transactions, :transaction_type
  end
end
