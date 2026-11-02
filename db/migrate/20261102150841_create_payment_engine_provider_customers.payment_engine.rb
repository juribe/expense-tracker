# This migration comes from payment_engine (originally 20261102000500)
class CreatePaymentEngineProviderCustomers < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_engine_provider_customers do |t|
      t.string :owner_type, null: false
      t.bigint :owner_id, null: false
      t.string :provider_code, null: false
      t.string :external_customer_id
      t.timestamps
    end
    add_index :payment_engine_provider_customers, [:owner_type, :owner_id, :provider_code], unique: true, name: "idx_pe_provider_customers_unique"
  end
end
