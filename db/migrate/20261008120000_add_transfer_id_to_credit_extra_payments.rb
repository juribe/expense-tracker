class AddTransferIdToCreditExtraPayments < ActiveRecord::Migration[7.1]
  def change
    add_reference :credit_extra_payments, :transfer, foreign_key: true
  end
end
