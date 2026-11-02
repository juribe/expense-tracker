class CreatePaymentEngineSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_engine_subscriptions do |t|
      t.string :owner_type, null: false
      t.string :owner_id, null: false
      t.references :payment_option, null: true, foreign_key: { to_table: :payment_engine_payment_options }
      t.string :provider_code
      t.string :external_id
      t.string :status, null: false, default: "active"
      t.datetime :starts_at
      t.datetime :next_billing_at
      t.datetime :last_payment_at
      t.datetime :last_failed_at
      t.timestamps
    end
    add_index :payment_engine_subscriptions, [:owner_type, :owner_id]
  end
end
