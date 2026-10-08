# frozen_string_literal: true

class LinkGoalsToPockets < ActiveRecord::Migration[8.0]
  def change
    remove_index :goals, [ :user_id, :name ]
    change_table :goals do |t|
      t.references :pocket, foreign_key: { to_table: :money_sources }
      t.integer :priority, default: 1, null: false
      t.string :category
      t.string :status, default: "active", null: false
    end
    add_index :goals, [ :user_id, :name ]

    remove_column :goals, :saved_amount
  end
end
