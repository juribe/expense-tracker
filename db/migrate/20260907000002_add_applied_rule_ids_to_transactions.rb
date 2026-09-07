# frozen_string_literal: true

class AddAppliedRuleIdsToTransactions < ActiveRecord::Migration[8.0]
  def change
    add_column :transactions, :applied_rule_ids, :jsonb, default: [], null: false
    add_column :transactions, :rule_id, :bigint, null: true
  end
end
