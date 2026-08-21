# frozen_string_literal: true

class RemapLegacyLinksToTransactions < ActiveRecord::Migration[8.0]
  def up
    remove_foreign_key :monthly_expense_payments, :expenses

    execute <<~SQL.squish
      UPDATE monthly_expense_payments
      SET expense_id = (
        SELECT t.id
        FROM transactions t
        JOIN expenses e
          ON e.id = monthly_expense_payments.expense_id
         AND t.kind = 'expense'
         AND t.user_id = e.user_id
         AND t.category_id = e.category_id
         AND t.date = e.date
         AND t.amount = e.amount
         AND COALESCE(t.description, '') = COALESCE(e.description, '')
        LIMIT 1
      )
      WHERE EXISTS (
        SELECT 1 FROM expenses e WHERE e.id = monthly_expense_payments.expense_id
      )
    SQL

    execute <<~SQL.squish
      UPDATE recurring_transaction_occurrences
      SET transaction_id = (
        SELECT t.id
        FROM transactions t
        JOIN incomes i
          ON i.id = recurring_transaction_occurrences.transaction_id
         AND recurring_transaction_occurrences.transaction_type = 'income'
         AND t.kind = 'income'
         AND t.user_id = i.user_id
         AND t.category_id = i.category_id
         AND t.date = i.date
         AND t.amount = i.amount
         AND COALESCE(t.description, '') = COALESCE(i.description, '')
        LIMIT 1
      )
      WHERE transaction_type = 'income'
    SQL

    execute <<~SQL.squish
      UPDATE recurring_transaction_occurrences
      SET transaction_id = (
        SELECT t.id
        FROM transactions t
        JOIN expenses e
          ON e.id = recurring_transaction_occurrences.transaction_id
         AND recurring_transaction_occurrences.transaction_type = 'expense'
         AND t.kind = 'expense'
         AND t.user_id = e.user_id
         AND t.category_id = e.category_id
         AND t.date = e.date
         AND t.amount = e.amount
         AND COALESCE(t.description, '') = COALESCE(e.description, '')
        LIMIT 1
      )
      WHERE transaction_type = 'expense'
    SQL

    add_foreign_key :monthly_expense_payments, :transactions, column: :expense_id
  end

  def down
    remove_foreign_key :monthly_expense_payments, column: :expense_id
    add_foreign_key :monthly_expense_payments, :expenses, column: :expense_id
  end
end
