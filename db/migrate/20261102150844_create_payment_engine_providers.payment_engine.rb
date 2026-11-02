# This migration comes from payment_engine (originally 20261102000800)
class CreatePaymentEngineProviders < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_engine_providers do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.string :environment, default: "sandbox"
      t.boolean :active, default: false
      t.jsonb :credentials, default: {}
      t.jsonb :settings, default: {}
      t.jsonb :capabilities, default: {}
      t.datetime :last_activity_at
      t.timestamps
    end
    add_index :payment_engine_providers, :code, unique: true
  end
end
