# This migration comes from payment_engine (originally 20261102000200)
class CreatePaymentEnginePurchases < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_engine_purchases do |t|
      t.string :code, null: false
      t.string :owner_type, null: false
      t.bigint :owner_id, null: false
      t.references :payment_option, null: true, foreign_key: { to_table: :payment_engine_payment_options }
      t.jsonb :commercial_snapshot, default: {}
      t.decimal :amount, precision: 15, scale: 2, null: false, default: 0
      t.string :currency, null: false, default: "COP"
      t.string :status, null: false, default: "pending"
      t.bigint :payment_id
      t.bigint :membership_id
      t.bigint :subscription_id
      t.timestamps
    end
    add_index :payment_engine_purchases, :code, unique: true
    add_index :payment_engine_purchases, [:owner_type, :owner_id]
  end
end
