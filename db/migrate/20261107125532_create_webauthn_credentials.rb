# frozen_string_literal: true

class CreateWebauthnCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :webauthn_credentials, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :external_id, null: false
      t.string :name, null: false
      t.text :public_key, null: false
      t.integer :sign_count, limit: 8, null: false
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.integer :authentication_factor, limit: 1, null: false

      t.timestamps
    end
    add_index :webauthn_credentials, :external_id, unique: true
  end
end
