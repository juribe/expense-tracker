# frozen_string_literal: true

class CreateMailInboundDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :mail_inbound_deliveries, id: :uuid do |t|
      t.string :provider, null: false
      t.string :external_id, null: false
      t.string :status, null: false, default: "received"
      t.text :raw_body
      t.jsonb :headers, null: false, default: {}
      t.jsonb :params, null: false, default: {}
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :processed_email, foreign_key: true, type: :uuid
      t.integer :attempts, null: false, default: 0
      t.string :last_error
      t.datetime :processed_at
      t.timestamps
    end

    add_index :mail_inbound_deliveries, [ :provider, :external_id ], unique: true
    add_index :mail_inbound_deliveries, :status
  end
end
