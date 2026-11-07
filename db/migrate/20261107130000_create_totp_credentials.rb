# frozen_string_literal: true

class CreateTotpCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :totp_credentials, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid, index: { unique: true }
      t.text :secret, null: false
      t.bigint :last_used_timestamp, null: false, default: 0

      t.timestamps
    end
  end
end
