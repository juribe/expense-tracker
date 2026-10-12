# frozen_string_literal: true

class AddDebtCapacitySettingsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :debt_capacity_target_percentage, :decimal, precision: 5, scale: 2, null: false, default: 30
    add_column :users, :debt_capacity_alert_percentage, :decimal, precision: 5, scale: 2, null: false, default: 40
  end
end
