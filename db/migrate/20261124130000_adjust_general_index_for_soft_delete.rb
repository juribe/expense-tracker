# frozen_string_literal: true

class AdjustGeneralIndexForSoftDelete < ActiveRecord::Migration[8.1]
  OLD_INDEX = "index_money_sources_general_per_user"

  def up
    remove_index :money_sources, name: OLD_INDEX

    # Existing soft-deleted General records were archived before the flag was
    # preserved. Restore the marker so switching back to simple can reuse them,
    # as long as the user has no active General.
    execute <<~SQL.squish
      UPDATE money_sources
      SET general = TRUE
      WHERE deleted_at IS NOT NULL
        AND general = FALSE
        AND name = 'General'
        AND kind IN ('general', 'account')
        AND NOT EXISTS (
          SELECT 1 FROM money_sources active_general
          WHERE active_general.user_id = money_sources.user_id
            AND active_general.general = TRUE
            AND active_general.deleted_at IS NULL
        )
    SQL

    add_index :money_sources, :user_id, unique: true,
              where: "general = TRUE AND deleted_at IS NULL",
              name: OLD_INDEX
  end

  def down
    remove_index :money_sources, name: OLD_INDEX

    execute "UPDATE money_sources SET general = FALSE WHERE deleted_at IS NOT NULL AND general = TRUE"

    add_index :money_sources, :user_id, unique: true,
              where: "(general = true)",
              name: OLD_INDEX
  end
end
