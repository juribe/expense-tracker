# frozen_string_literal: true

class BackfillTransactionsAndTemplates < ActiveRecord::Migration[8.0]
  def up
    now = Time.current

    execute <<~SQL.squish
      INSERT INTO transactions (user_id, category_id, date, amount, kind, description, source, created_at, updated_at)
      SELECT user_id, category_id, date, amount, 'income', description, 'manual', created_at, updated_at
      FROM incomes
    SQL

    execute <<~SQL.squish
      INSERT INTO transactions (user_id, category_id, date, amount, kind, description, source, created_at, updated_at)
      SELECT user_id, category_id, date, amount, 'expense', description, 'manual', created_at, updated_at
      FROM expenses
    SQL

    execute <<~SQL.squish
      INSERT INTO recurring_templates (user_id, category_id, kind, amount, description, payment_day, frequency, active, source, created_at, updated_at)
      SELECT user_id, category_id, 'expense', amount, description, payment_day, 'monthly', active, 'monthly_expense', created_at, updated_at
      FROM monthly_expenses
    SQL

    execute <<~SQL.squish
      INSERT INTO recurring_templates (user_id, category_id, kind, amount, description, payment_day, frequency, active, source, created_at, updated_at)
      SELECT user_id, category_id, transaction_type, amount, description, payment_day, frequency, active, 'recurring_transaction', created_at, updated_at
      FROM recurring_transactions
    SQL
  end

  def down
    execute "DELETE FROM recurring_templates"
    execute "DELETE FROM transactions"
  end
end
