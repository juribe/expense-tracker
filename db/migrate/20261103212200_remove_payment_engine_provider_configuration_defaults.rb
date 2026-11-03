# frozen_string_literal: true

class RemovePaymentEngineProviderConfigurationDefaults < ActiveRecord::Migration[8.1]
  def up
    change_column_default :payment_engine_providers, :credentials, from: "{}", to: nil
    change_column_default :payment_engine_providers, :settings, from: "{}", to: nil
  end

  def down
    change_column_default :payment_engine_providers, :credentials, from: nil, to: "{}"
    change_column_default :payment_engine_providers, :settings, from: nil, to: "{}"
  end
end
