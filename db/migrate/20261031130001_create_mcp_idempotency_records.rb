# frozen_string_literal: true

class CreateMcpIdempotencyRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :mcp_idempotency_records, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :idempotency_key, null: false
      t.string :tool_name, null: false
      t.string :request_digest, null: false
      t.jsonb :response, null: false, default: {}
      t.uuid :resource_id
      t.timestamps
    end

    add_index :mcp_idempotency_records, [ :user_id, :idempotency_key ], unique: true
  end
end
