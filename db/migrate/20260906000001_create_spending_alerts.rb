# frozen_string_literal: true

class CreateSpendingAlerts < ActiveRecord::Migration[8.0]
  def change
    create_table :spending_alerts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :month, null: false
      t.integer :pct, null: false
      t.decimal :amount, null: false, precision: 14, scale: 2
      t.decimal :previous_amount, precision: 14, scale: 2
      t.datetime :read_at
      t.timestamps
    end

    # Deduplication guarantee: at most one alert per (kind, category, month).
    add_index :spending_alerts, [ :user_id, :kind, :category_id, :month ],
              unique: true, name: "index_spending_alerts_on_kind_category_month"
    add_index :spending_alerts, [ :user_id, :read_at ]
  end
end