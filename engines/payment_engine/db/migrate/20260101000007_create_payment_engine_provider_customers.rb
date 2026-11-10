class CreatePaymentEngineProviderCustomers < ActiveRecord::Migration[7.2]
  def change
    create_table :payment_engine_provider_customers do |t|
      t.string :owner_type, null: false
      t.bigint :owner_id, null: false
      t.string :provider, null: false
      t.string :provider_customer_id, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :payment_engine_provider_customers, [ :owner_type, :owner_id ]
    add_index :payment_engine_provider_customers, [ :owner_type, :owner_id, :provider ],
              unique: true,
              name: "index_payment_engine_provider_customers_unique_owner"
    add_index :payment_engine_provider_customers, [ :provider, :provider_customer_id ],
              unique: true,
              name: "index_payment_engine_provider_customers_unique_provider_id"
  end
end
