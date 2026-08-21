# frozen_string_literal: true

class AddFrequencyToTransactions < ActiveRecord::Migration[8.0]
  def change
    add_column :transactions, :frequency, :string, null: false, default: "one_time"
    add_index :transactions, :frequency
    add_index :transactions, [ :user_id, :frequency ]
  end
end
