# This migration comes from payment_engine (originally 20261102000900)
class CreatePaymentEngineSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_engine_settings do |t|
      t.string :default_currency, default: "COP"
      t.string :time_zone, default: "UTC"
      t.string :locale, default: "es"
      t.string :membership_policy, default: "single"
      t.string :expiration_policy, default: "end_of_period"
      t.integer :grace_days, default: 3
      t.string :cancellation_policy, default: "end_of_period"
      t.boolean :audit_enabled, default: true
      t.string :notification_email
      t.timestamps
    end
  end
end
