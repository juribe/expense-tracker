# This migration comes from payment_engine (originally 20261102000001)
class CreatePaymentEnginePaymentOptions < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_engine_payment_options do |t|
      t.references :membership_type, null: false, foreign_key: { to_table: :payment_engine_membership_types }
      t.string :name, null: false
      t.text :description
      t.decimal :price, precision: 15, scale: 2, null: false, default: 0
      t.string :currency, null: false, default: "COP"
      t.string :mode, null: false, default: "one_time"
      t.string :interval, default: "month"
      t.integer :interval_count, default: 1
      t.integer :trial_days, default: 0
      t.string :status, null: false, default: "active"
      t.integer :position, default: 0
      t.timestamps
    end
  end
end
