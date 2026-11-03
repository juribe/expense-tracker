# frozen_string_literal: true

class EncryptExistingPaymentEngineProviderConfiguration < ActiveRecord::Migration[8.1]
  def up
    previous_setting = ActiveRecord::Encryption.config.support_unencrypted_data
    ActiveRecord::Encryption.config.support_unencrypted_data = true

    PaymentEngine::Provider.reset_column_information
    PaymentEngine::Provider.find_each do |provider|
      provider.credentials_will_change!
      provider.settings_will_change!
      provider.save!(validate: false)
    end
  ensure
    ActiveRecord::Encryption.config.support_unencrypted_data = previous_setting
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "Encrypted provider credentials cannot be decrypted automatically."
  end
end
