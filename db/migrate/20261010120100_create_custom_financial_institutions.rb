# frozen_string_literal: true

# User-owned financial institutions ("Otra entidad"). Private to their owner:
# never shown to other users (Global enunciado: CustomFinancialInstitution),
# never merged into the shared catalog, and shared across all of the owner's
# money sources.
class CreateCustomFinancialInstitutions < ActiveRecord::Migration[8.0]
  def change
    create_table :custom_financial_institutions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :institution_type
      t.timestamps

      t.index [ :user_id, :name ], unique: true,
              name: "index_custom_financial_institutions_on_user_id_and_name"
    end
  end
end
