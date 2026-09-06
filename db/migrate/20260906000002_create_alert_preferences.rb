# frozen_string_literal: true

class CreateAlertPreferences < ActiveRecord::Migration[8.0]
  def change
    # unique: true on the reference avoids the duplicate-index name collision
    # (t.references would otherwise create index_alert_preferences_on_user_id
    # and then add_index would try to create it again).
    create_table :alert_preferences do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.boolean :budget_threshold_enabled, null: false, default: true
      t.boolean :budget_exceeded_enabled, null: false, default: true
      t.boolean :spending_increase_enabled, null: false, default: false
      t.timestamps
    end
  end
end