class AddOutstandingUsageReplayedToCreditAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :credit_accounts, :outstanding_usage_replayed, :boolean, default: false, null: false
  end
end
