# frozen_string_literal: true

class MigrateMoneySourceIdentifiersToTags < ActiveRecord::Migration[8.0]
  # Copies every money_source_identifier into money_source_tags using the same
  # normalization the old model applied per kind, so no existing data is lost.
  def up
    execute <<~SQL
      INSERT INTO money_source_tags (money_source_id, value, created_at, updated_at)
      SELECT DISTINCT msi.money_source_id,
             CASE msi.kind
               WHEN 'card_last_four' THEN right(regexp_replace(msi.value, '[^0-9]', '', 'g'), 4)
               WHEN 'bank_name' THEN lower(btrim(msi.value))
               WHEN 'account_number' THEN regexp_replace(msi.value, '[^0-9]', '', 'g')
               ELSE lower(btrim(msi.value))
             END,
             now(), now()
      FROM money_source_identifiers msi
      WHERE EXISTS (SELECT 1 FROM money_sources ms WHERE ms.id = msi.money_source_id)
    SQL
  end

  def down
    # No-op: the original identifiers are still preserved in their own table.
  end
end