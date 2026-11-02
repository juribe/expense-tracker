class CreatePaymentEnginePayments < ActiveRecord::Migration[7.2]
  def change
    create_table :payment_engine_payments do |t|
      t.references :purchase, null: false,
                   foreign_key: { to_table: :payment_engine_purchases },
                   index: { name: "index_payment_engine_payments_on_purchase_id" }
      t.references :membership, null: true,
                   foreign_key: { to_table: :payment_engine_memberships },
                   index: { name: "index_payment_engine_payments_on_membership_id" }
      t.string :provider, null: false
      t.string :provider_transaction_id
      t.bigint :amount, null: false, default: 0
      t.string :currency, null: false, limit: 3
      t.string :status, null: false, default: "pending"
      t.string :payment_method
      t.datetime :paid_at
      t.text :failure_reason
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :payment_engine_payments, [ :provider, :provider_transaction_id ],
              unique: true,
              where: "provider_transaction_id IS NOT NULL",
              name: "index_payment_engine_payments_unique_provider_transaction"
    add_index :payment_engine_payments, [ :status, :created_at ]
    add_check_constraint :payment_engine_payments, "amount >= 0", name: "payments_amount_non_negative"
    add_check_constraint :payment_engine_payments,
                         "status IN ('pending', 'processing', 'approved', 'rejected', 'canceled', 'refunded', 'partially_refunded')",
                         name: "payments_status_valid"
  end
end
