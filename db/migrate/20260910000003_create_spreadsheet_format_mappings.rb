# frozen_string_literal: true

# Known spreadsheet formats. When an import's header fingerprint matches a
# stored mapping, every row is processed deterministically without any AI
# call; AI is only used the first time an unknown format shows up.
class CreateSpreadsheetFormatMappings < ActiveRecord::Migration[8.0]
  def change
    create_table :spreadsheet_format_mappings do |t|
      t.references :user, null: false, foreign_key: true
      t.string :fingerprint, null: false
      t.string :bank
      t.jsonb :headers, null: false, default: []
      t.jsonb :mapping, null: false, default: {}
      t.decimal :confidence, precision: 4, scale: 3
      t.string :source, null: false, default: "ai"
      t.timestamps
    end

    add_index :spreadsheet_format_mappings, %i[user_id fingerprint], unique: true
  end
end
