# frozen_string_literal: true

class AddRecurringPaidInFullToTransactions < ActiveRecord::Migration[8.0]
  def change
    add_column :transactions, :recurring_paid_in_full, :boolean, default: false, null: false
  end
end
