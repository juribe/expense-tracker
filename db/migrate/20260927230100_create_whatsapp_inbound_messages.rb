# Inbound WhatsApp message ids (wamid...) already processed. WhatsApp Cloud
# API re-delivers webhooks on timeouts and network blips; the unique index on
# mid makes duplicate deliveries and concurrent jobs idempotent.
class CreateWhatsappInboundMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :whatsapp_inbound_messages do |t|
      t.string :mid, null: false
      t.datetime :processed_at, null: false

      t.timestamps
    end

    add_index :whatsapp_inbound_messages, :mid, unique: true
  end
end
