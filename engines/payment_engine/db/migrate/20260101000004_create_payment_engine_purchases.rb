class CreatePaymentEnginePurchases < ActiveRecord::Migration[7.2]
  def change
    create_table :payment_engine_purchases do |t|
      t.string :owner_type, null: false
      t.bigint :owner_id, null: false
      t.references :payment_option, null: false,
                   foreign_key: { to_table: :payment_engine_payment_options },
                   index: { name: "index_payment_engine_purchases_on_payment_option_id" }
      t.references :membership, null: true,
                   foreign_key: { to_table: :payment_engine_memberships },
                   index: { name: "index_payment_engine_purchases_on_membership_id" }
      t.string :status, null: false, default: "pending"
      t.bigint :amount, null: false, default: 0
      t.string :currency, null: false, limit: 3
      t.string :provider
      t.string :description
      t.datetime :purchased_at

      t.string :option_name
      t.string :membership_type_name
      t.bigint :price
      t.jsonb :duration, null: false, default: {}
      t.string :billing_type

      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :payment_engine_purchases, [ :owner_type, :owner_id ]
    add_index :payment_engine_purchases, [ :status, :created_at ]
    add_index :payment_engine_purchases, :provider
    add_check_constraint :payment_engine_purchases, "amount >= 0", name: "purchases_amount_non_negative"
    add_check_constraint :payment_engine_purchases, "price IS NULL OR price >= 0", name: "purchases_price_non_negative"
    add_check_constraint :payment_engine_purchases,
                         "status IN ('pending', 'processing', 'completed', 'failed', 'canceled', 'refunded')",
                         name: "purchases_status_valid"
  end
end
