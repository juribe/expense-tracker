# frozen_string_literal: true

class CreateBudgets < ActiveRecord::Migration[8.0]
  def change
    create_table :budgets do |t|
      t.references :user, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.decimal :monthly_amount, null: false, precision: 14, scale: 2
      t.string :period, null: false, default: "monthly"
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :budgets, [ :user_id, :category_id ], unique: true
  end
end