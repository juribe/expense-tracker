class FixCreditExtraPaymentExpenseFk < ActiveRecord::Migration[8.0]
  # Environments that ran the reference against the legacy "expenses" table
  # need to be pointed at the real one: expenses live in :transactions
  # (Expense < Transaction).
  def up
    remove_foreign_key :credit_extra_payments, to_table: :expenses if foreign_key_exists?(:credit_extra_payments, :expenses)
    return if foreign_key_exists?(:credit_extra_payments, :transactions, column: :expense_id)

    add_foreign_key :credit_extra_payments, :transactions, column: :expense_id
  end

  def down
    remove_foreign_key :credit_extra_payments, to_table: :transactions, column: :expense_id if foreign_key_exists?(:credit_extra_payments, :transactions, column: :expense_id)
  end
end
