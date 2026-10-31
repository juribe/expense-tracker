# frozen_string_literal: true

class CreateMcpToolInvocations < ActiveRecord::Migration[8.1]
  def change
    create_table :mcp_tool_invocations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :mcp_access_token, type: :uuid, foreign_key: { on_delete: :nullify }
      t.string :tool_name, null: false
      t.string :status, null: false
      t.string :error_code
      t.uuid :resource_id
      t.jsonb :argument_keys, null: false, default: []
      t.timestamps
    end

    add_index :mcp_tool_invocations, [ :user_id, :created_at ]
    add_index :mcp_tool_invocations, :tool_name
  end
end
