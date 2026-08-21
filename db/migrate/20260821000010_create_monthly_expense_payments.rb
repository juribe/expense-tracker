# frozen_string_literal: true

class CreateMonthlyExpensePayments < ActiveRecord::Migration[8.0]
  def change
    create_table :monthly_expense_payments do |t|
      t.references :monthly_expense, null: false, foreign_key: true
      t.references :expense, null: false, foreign_key: true
      t.date :payment_date, null: false
      t.timestamps
    end

    add_index :monthly_expense_payments, [ :monthly_expense_id, :payment_date ],
              name: "index_monthly_expense_payments_on_me_and_payment_date"
  end
end
