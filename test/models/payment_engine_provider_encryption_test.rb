# frozen_string_literal: true

require "test_helper"

class PaymentEngineProviderEncryptionTest < ActiveSupport::TestCase
  setup do
    @provider = PaymentEngine::Provider.create!(
      code: "encryption-test-#{SecureRandom.hex(4)}",
      name: "Encryption Test",
      environment: "sandbox",
      active: true,
      credentials: { "public_key" => "public-secret", "private_key" => "private-secret" },
      settings: { "webhook_secret" => "settings-secret" }
    )
  end

  test "credentials and settings are encrypted at rest" do
    raw = raw_columns(@provider.id)

    assert_not_includes raw[:credentials].to_s, "public-secret"
    assert_not_includes raw[:credentials].to_s, "private-secret"
    assert_not_includes raw[:settings].to_s, "settings-secret"
  end

  test "encrypted credentials and settings are readable through the model" do
    provider = PaymentEngine::Provider.find(@provider.id)

    assert_equal "public-secret", provider.credentials["public_key"]
    assert_equal "private-secret", provider.credentials["private_key"]
    assert_equal "settings-secret", provider.settings["webhook_secret"]
  end

  test "provider settings resolve encrypted credentials and settings" do
    settings = PaymentEngine.provider_settings_for(@provider.code)

    assert_equal "public-secret", settings[:public_key]
    assert_equal "settings-secret", settings[:webhook_secret]
  end

  test "legacy plaintext values are rejected by default and re-encrypted by the backfill" do
    connection = PaymentEngine::Provider.connection
    connection.execute <<~SQL.squish
      UPDATE payment_engine_providers
      SET credentials = '{"p_key":"legacy-secret"}', settings = '{"legacy":"value"}'
      WHERE id = #{connection.quote(@provider.id)}
    SQL

    provider = PaymentEngine::Provider.find(@provider.id)
    assert_raises(ActiveRecord::Encryption::Errors::Decryption) { provider.credentials }

    previous = ActiveRecord::Encryption.config.support_unencrypted_data
    begin
      ActiveRecord::Encryption.config.support_unencrypted_data = true
      EncryptionBackfill.run!
    ensure
      ActiveRecord::Encryption.config.support_unencrypted_data = previous
    end

    raw = raw_columns(@provider.id)
    assert_not_includes raw[:credentials].to_s, "legacy-secret"

    provider = PaymentEngine::Provider.find(@provider.id)
    assert_equal "legacy-secret", provider.credentials["p_key"]
    assert_equal "value", provider.settings["legacy"]
  end

  private

  def raw_columns(id)
    PaymentEngine::Provider.connection.select_one(
      "SELECT credentials, settings FROM payment_engine_providers WHERE id = #{PaymentEngine::Provider.connection.quote(id)}"
    ).symbolize_keys
  end
end
