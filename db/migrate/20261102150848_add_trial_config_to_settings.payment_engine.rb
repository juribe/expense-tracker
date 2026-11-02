class AddTrialConfigToSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :payment_engine_settings, :payments_enabled, :boolean, default: true, null: false
    add_column :payment_engine_settings, :paid_access_required, :boolean, default: true, null: false
    add_column :payment_engine_settings, :free_trial_enabled, :boolean, default: true, null: false
    add_column :payment_engine_settings, :free_trial_duration_days, :integer, default: 60, null: false
    add_column :payment_engine_settings, :free_trial_requires_card, :boolean, default: false, null: false
    add_column :payment_engine_settings, :free_trial_once_per_user, :boolean, default: true, null: false
  end
end
