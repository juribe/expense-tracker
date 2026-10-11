# frozen_string_literal: true

# Adds the shared catalog identity to FinancialInstitution: a stable `slug`
# (the key seeds and forms rely on) and `institution_type` (bank /
# digital_bank / digital_wallet / financing_company / other). Existing rows
# are backfilled from canonical_name.
class AddSlugAndInstitutionTypeToFinancialInstitutions < ActiveRecord::Migration[8.0]
  def change
    add_column :financial_institutions, :slug, :string
    add_column :financial_institutions, :institution_type, :string

    add_index :financial_institutions, :slug, unique: true
    add_index :financial_institutions, :institution_type

    # Backfill slugs for pre-existing seeded institutions. Only fills blanks
    # so the migration is safe to re-run on partially migrated data.
    reversible do |dir|
      dir.up do
        FinancialInstitution.where(slug: nil).find_each do |institution|
          institution.update_columns(slug: institution.canonical_name.parameterize)
        end
      end
    end

    change_column_null :financial_institutions, :slug, false
  end
end
