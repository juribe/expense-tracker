# frozen_string_literal: true

class CreateMonthlyExpenses < ActiveRecord::Migration[8.0]
  def change
    create_table :monthly_expenses do |t|
      t.references :user, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.decimal :amount, null: false, precision: 10, scale: 2
      t.string :description
      # Day of the month when this expense is normally due
      t.integer :payment_day
      t.boolean :active, default: true, null: false
      t.timestamps
    end
  end
end
