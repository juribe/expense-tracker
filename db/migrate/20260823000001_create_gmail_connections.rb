# frozen_string_literal: true

class CreateGmailConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :gmail_connections do |t|
      t.references :user, null: false, foreign_key: true

      t.string :email, null: false
      t.string :google_account_id

      # OAuth credentials (stored encrypted at rest by the model layer).
      t.string :access_token
      t.string :refresh_token
      t.datetime :token_expires_at

      # Configurable criteria used to identify transaction emails.
      t.json :search_config, default: {}

      t.datetime :last_synced_at
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :gmail_connections, [:user_id, :email], unique: true
  end
end
