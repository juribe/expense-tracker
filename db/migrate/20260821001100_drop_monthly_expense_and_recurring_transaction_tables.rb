# frozen_string_literal: true

class DropMonthlyExpenseAndRecurringTransactionTables < ActiveRecord::Migration[8.0]
  def up
    drop_table :monthly_expense_payments, if_exists: true
    drop_table :monthly_expenses, if_exists: true
    drop_table :recurring_transaction_occurrences, if_exists: true
    drop_table :recurring_transactions, if_exists: true
  end

  def down
    create_table :recurring_transactions do |t|
      t.integer :user_id, null: false
      t.integer :category_id, null: false
      t.string :transaction_type, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :description
      t.string :frequency, default: "monthly", null: false
      t.integer :payment_day
      t.boolean :active, default: true, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end

    create_table :recurring_transaction_occurrences do |t|
      t.integer :recurring_transaction_id, null: false
      t.string :transaction_type, null: false
      t.integer :transaction_id, null: false
      t.date :transaction_date, null: false
      t.string :period, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end

    create_table :monthly_expenses do |t|
      t.integer :user_id, null: false
      t.integer :category_id, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :description
      t.integer :payment_day
      t.boolean :active, default: true, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end

    create_table :monthly_expense_payments do |t|
      t.integer :monthly_expense_id, null: false
      t.integer :expense_id, null: false
      t.date :payment_date, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end
  end
end
