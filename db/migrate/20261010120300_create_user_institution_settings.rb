# frozen_string_literal: true

# Private per-user recognition settings tied to a financial institution
# (global or custom). One setting per user+institution; the typed values
# (UserInstitutionSettingValue, kinds: sender / domain / subject / header /
# keyword) mirror the MoneySourceRecognitionIdentifier convention so the
# chip editor and matcher scoring can be reused. These values belong
# exclusively to the user who enters them.
class CreateUserInstitutionSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :user_institution_settings do |t|
      t.references :user, null: false, foreign_key: true
      t.string :institution_type, null: false
      t.bigint :institution_id, null: false
      t.timestamps

      t.index [ :user_id, :institution_type, :institution_id ],
              unique: true,
              name: "index_user_institution_settings_unique_per_institution"
      t.index [ :institution_type, :institution_id ]
    end

    create_table :user_institution_setting_values do |t|
      t.references :user_institution_setting, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :value, null: false
      t.integer :position, null: false, default: 0
      t.timestamps

      t.index [ :user_institution_setting_id, :kind, :value ],
              unique: true,
              name: "index_uisv_on_setting_kind_value"
      t.index [ :user_institution_setting_id, :kind ],
              name: "index_uisv_on_setting_kind"
      t.index [ :user_institution_setting_id, :kind, :position ],
              name: "index_uisv_on_setting_kind_position"
    end
  end
end
