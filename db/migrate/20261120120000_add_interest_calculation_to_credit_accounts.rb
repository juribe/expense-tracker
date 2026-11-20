# frozen_string_literal: true

class AddInterestCalculationToCreditAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :credit_accounts, :interest_calculation_enabled, :boolean, default: false, null: false
    add_column :credit_accounts, :interest_calculation_date, :date
  end
end
