# frozen_string_literal: true

class CreateUserConsents < ActiveRecord::Migration[8.1]
  def change
    create_table :user_consents, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :consent_type, null: false
      t.string :document_version
      t.boolean :granted, null: false, default: true
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :user_consents, [ :user_id, :consent_type, :occurred_at ]
  end
end
