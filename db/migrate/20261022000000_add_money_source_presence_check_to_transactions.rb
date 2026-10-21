class AddMoneySourcePresenceCheckToTransactions < ActiveRecord::Migration[8.1]
  def up
    add_check_constraint :transactions,
                         "kind NOT IN ('expense', 'income') OR money_source_id IS NOT NULL",
                         name: "transactions_money_source_presence"
  end

  def down
    remove_check_constraint :transactions, name: "transactions_money_source_presence"
  end
end
