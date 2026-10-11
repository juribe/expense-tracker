# frozen_string_literal: true

# Denormalizes the institution display name onto the money source row so
# views/badges/reports never need the polymorphic lookup at render time
# (same pattern as cached_balance / transactions_count). Derived data only:
# the backfill is safe to re-run and never touches user-owned attributes.
#
# Upkeep lives in MoneySource#sync_institution_cached_name (before_save) and
# in the entity-level after_update name-change cascade.
class AddInstitutionCachedNameToMoneySources < ActiveRecord::Migration[8.0]
  def change
    add_column :money_sources, :institution_cached_name, :string

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE money_sources
          SET institution_cached_name = COALESCE(
            CASE
              WHEN institution_type = 'FinancialInstitution' THEN
                (SELECT canonical_name FROM financial_institutions
                  WHERE financial_institutions.id = money_sources.institution_id)
              WHEN institution_type = 'CustomFinancialInstitution' THEN
                (SELECT name FROM custom_financial_institutions
                  WHERE custom_financial_institutions.id = money_sources.institution_id)
            END,
            NULL
          )
        SQL
      end
    end
  end
end
