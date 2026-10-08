class MakeCreditExtraPaymentsReal < ActiveRecord::Migration[8.0]
  def change
    change_table :credit_extra_payments do |t|
      t.references :funding_money_source, foreign_key: { to_table: :money_sources }
      # Expense and Payment both live in the single-transactions design: the
      # expense row is a Transaction; the payment links to payments.
      t.references :payment, foreign_key: true
      t.references :expense, foreign_key: { to_table: :transactions }
    end
  end
end
