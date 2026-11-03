# frozen_string_literal: true

class EncryptPaymentEngineProviderConfiguration < ActiveRecord::Migration[8.1]
  def up
    change_column :payment_engine_providers, :credentials, :text, using: "credentials::text"
    change_column :payment_engine_providers, :settings, :text, using: "settings::text"
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "Encrypted provider credentials cannot be converted back to jsonb automatically."
  end
end
