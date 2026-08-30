# frozen_string_literal: true

class CreateCreditAccounts < ActiveRecord::Migration[8.0]
  def change
    create_table :credit_accounts do |t|
      t.references :money_source, null: false, foreign_key: true, index: { unique: true }

      # Common credit/debt attributes
      t.decimal :credit_limit, precision: 14, scale: 2
      t.decimal :interest_rate, precision: 8, scale: 4
      t.string :interest_rate_type

      # Credit card identification (never the full number / CVV / PIN)
      t.string :card_brand
      t.string :card_last_four

      # Credit card billing cycle (days of the month)
      t.integer :statement_day
      t.integer :payment_due_day

      # Loan / installment-loan attributes
      t.decimal :principal_amount, precision: 14, scale: 2
      t.decimal :outstanding_balance, precision: 14, scale: 2
      t.decimal :installment_amount, precision: 14, scale: 2
      t.integer :installment_count
      t.string :payment_frequency
      t.date :start_date
      t.date :end_date

      t.timestamps
    end
  end
end
