# frozen_string_literal: true

class CreateGoalAllocations < ActiveRecord::Migration[8.0]
  def change
    create_table :goal_allocations do |t|
      t.references :financial_goal, null: false, foreign_key: { to_table: :goals }
      t.references :pocket, null: false, foreign_key: { to_table: :money_sources }
      t.decimal :amount, precision: 14, scale: 2, null: false
      t.date :date, null: false
      t.string :note

      t.timestamps
    end

    add_index :goal_allocations, [ :pocket_id, :date ]
  end
end
