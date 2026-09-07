# frozen_string_literal: true

class CreateTransactionRules < ActiveRecord::Migration[8.0]
  def change
    create_table :transaction_rules do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.boolean :enabled, default: true, null: false
      t.integer :priority, default: 0, null: false

      # Condition columns (nullable — only the ones set are checked)
      t.string :merchant_contains
      t.string :description_contains
      t.bigint :money_source_condition_id
      t.decimal :amount_gt, precision: 14, scale: 2
      t.decimal :amount_lt, precision: 14, scale: 2

      # Action columns (nullable — only the ones set are applied)
      t.references :category, foreign_key: true
      t.bigint :action_money_source_id
      t.string :tag

      t.timestamps
    end

    add_index :transaction_rules, :priority, order: :desc
    add_foreign_key :transaction_rules, :money_sources, column: :money_source_condition_id
    add_foreign_key :transaction_rules, :money_sources, column: :action_money_source_id
  end
end
