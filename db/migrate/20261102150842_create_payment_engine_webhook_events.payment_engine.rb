# This migration comes from payment_engine (originally 20261102000600)
class CreatePaymentEngineWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_engine_webhook_events do |t|
      t.string :provider_code, null: false
      t.string :external_id
      t.string :event_type
      t.string :status, null: false, default: "received"
      t.jsonb :payload, default: {}
      t.text :processing_result
      t.integer :attempts, default: 0
      t.datetime :received_at
      t.datetime :processed_at
      t.timestamps
    end
    add_index :payment_engine_webhook_events, [:provider_code, :external_id], unique: true, name: "idx_pe_webhook_unique"
  end
end
