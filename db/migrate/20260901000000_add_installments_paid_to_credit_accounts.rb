class AddInstallmentsPaidToCreditAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :credit_accounts, :installments_paid, :integer
  end
end
