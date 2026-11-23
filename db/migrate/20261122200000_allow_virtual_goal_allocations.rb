# frozen_string_literal: true

class AllowVirtualGoalAllocations < ActiveRecord::Migration[8.1]
  def change
    change_column_null :goal_allocations, :pocket_id, true
    add_column :goal_allocations, :idempotency_key, :uuid
    add_index :goal_allocations, [ :financial_goal_id, :idempotency_key ],
              unique: true,
              where: "idempotency_key IS NOT NULL",
              name: "index_goal_allocations_on_goal_and_idempotency"
  end
end
