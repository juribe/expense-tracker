# frozen_string_literal: true

class CreateRecoveryCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :recovery_codes, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :code_digest, null: false
      t.datetime :used_at

      t.timestamps
    end
    add_index :recovery_codes, [ :user_id, :used_at ]
  end
end
