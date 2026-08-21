# frozen_string_literal: true

class RemoveFrequencyFromTransactions < ActiveRecord::Migration[8.0]
  def up
    remove_index :transactions, [ :user_id, :frequency ] if index_exists?(:transactions, [ :user_id, :frequency ])
    remove_index :transactions, :frequency if index_exists?(:transactions, :frequency)
    remove_column :transactions, :frequency, :string
  end

  def down
    add_column :transactions, :frequency, :string, null: false, default: "one_time"
    add_index :transactions, :frequency
    add_index :transactions, [ :user_id, :frequency ]
  end
end
