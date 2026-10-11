# frozen_string_literal: true

# The per-entity private settings layer (UserInstitutionSetting) never
# shipped to real users: bank-level recognition was redistributed into the
# money-source recognition groups (the seed source carries the bank
# configuration). Dropping the now-unused tables.
class DropUserInstitutionSettingsTables < ActiveRecord::Migration[8.0]
  def up
    drop_table :user_institution_setting_values if table_exists?(:user_institution_setting_values)
    drop_table :user_institution_settings if table_exists?(:user_institution_settings)
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Recreate via orphaned migrations history if ever needed"
  end
end
