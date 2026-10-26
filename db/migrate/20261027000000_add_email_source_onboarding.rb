# frozen_string_literal: true

class AddEmailSourceOnboarding < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :inbound_email_token, :string
    add_index :users, :inbound_email_token, unique: true

    create_table :email_sources, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :source_type, null: false, default: "forwarding"
      t.string :email
      t.string :status, null: false, default: "pending_setup"
      t.text :last_error
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :email_sources, [:user_id, :status]

    create_table :email_forwarding_verifications, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :email_source, foreign_key: { to_table: :email_sources }, type: :uuid
      t.string :code
      t.text :confirmation_url
      t.string :sender_email
      t.string :subject
      t.string :message_id
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end
    add_index :email_forwarding_verifications, [:user_id, :expires_at]
  end
end