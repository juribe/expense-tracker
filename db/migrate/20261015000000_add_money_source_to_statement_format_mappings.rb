# frozen_string_literal: true

# Scopes learned statement layouts to the money source they were learned from:
# the first upload of a card's statement teaches the recipe and every later
# upload of that same card reuses it deterministically. Recipes without a
# money source can no longer be matched, so the stale rows are dropped and
# re-learned on the next upload.
class AddMoneySourceToStatementFormatMappings < ActiveRecord::Migration[8.0]
  def up
    add_reference :statement_format_mappings, :money_source, foreign_key: true
    execute "DELETE FROM statement_format_mappings WHERE money_source_id IS NULL"
    change_column_null :statement_format_mappings, :money_source_id, false

    remove_index :statement_format_mappings, name: "index_statement_format_mappings_on_user_id_and_fingerprint"
    add_index :statement_format_mappings, %i[user_id money_source_id fingerprint],
              unique: true, name: "index_statement_format_mappings_source_fingerprint"
  end

  def down
    remove_index :statement_format_mappings, name: "index_statement_format_mappings_source_fingerprint"
    add_index :statement_format_mappings, %i[user_id fingerprint], unique: true
    remove_reference :statement_format_mappings, :money_source
  end
end
