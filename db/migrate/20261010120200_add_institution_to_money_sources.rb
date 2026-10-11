# frozen_string_literal: true

# Links each money source to its (optional) financial institution with a
# polymorphic association: FinancialInstitution (global catalog) or
# CustomFinancialInstitution (user-owned). The legacy free-text `bank`
# column is kept untouched as historical data / fallback.
class AddInstitutionToMoneySources < ActiveRecord::Migration[8.0]
  def change
    add_column :money_sources, :institution_type, :string
    add_column :money_sources, :institution_id, :bigint
    add_index :money_sources, [ :institution_type, :institution_id ],
              name: "index_money_sources_on_institution"
  end
end
