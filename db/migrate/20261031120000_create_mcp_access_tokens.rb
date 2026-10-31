# frozen_string_literal: true

class CreateMcpAccessTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :mcp_access_tokens, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :token_digest, null: false
      t.jsonb :scopes, null: false, default: [ "read" ]
      t.datetime :last_used_at
      t.datetime :expires_at
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :mcp_access_tokens, :token_digest, unique: true
  end
end
