# frozen_string_literal: true

# Learned statement layouts. The first time a bank statement layout is seen,
# the AI extracts its transactions and describes the row structure; that
# recipe is stored here keyed by the layout fingerprint, so later statements
# of the same format are parsed deterministically without any AI call.
class CreateStatementFormatMappings < ActiveRecord::Migration[8.0]
  def change
    create_table :statement_format_mappings do |t|
      t.references :user, null: false, foreign_key: true
      t.string :fingerprint, null: false
      t.string :bank
      t.jsonb :anchors, null: false, default: []
      t.jsonb :sections, null: false, default: {}
      t.jsonb :row_spec, null: false, default: {}
      t.boolean :skip_income, null: false, default: true
      t.decimal :confidence, precision: 4, scale: 3
      t.string :source, null: false, default: "ai"
      t.timestamps
    end

    add_index :statement_format_mappings, %i[user_id fingerprint], unique: true
  end
end
