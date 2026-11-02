class CreatePaymentEngineWebhookEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :payment_engine_webhook_events do |t|
      t.string :provider, null: false
      t.string :event_id, null: false
      t.string :event_type
      t.jsonb :payload, null: false, default: {}
      t.string :status, null: false, default: "received"
      t.datetime :received_at, null: false
      t.datetime :processed_at
      t.text :error_message
      t.integer :attempts, null: false, default: 0

      t.timestamps
    end

    add_index :payment_engine_webhook_events, [ :provider, :event_id ], unique: true
    add_index :payment_engine_webhook_events, [ :status, :received_at ]
    add_check_constraint :payment_engine_webhook_events,
                         "status IN ('received', 'processing', 'processed', 'failed', 'ignored')",
                         name: "webhook_events_status_valid"
  end
end
