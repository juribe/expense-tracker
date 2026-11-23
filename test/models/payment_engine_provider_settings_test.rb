# frozen_string_literal: true

require "test_helper"

# The ePayco adapter decides between sandbox and production from
# settings[:environment]. Those settings are resolved from the provider
# record saved in the admin UI, so the persisted environment must be part of
# the resolved hash.
class PaymentEngineProviderSettingsTest < ActiveSupport::TestCase
  PurchaseStub = Struct.new(:id, :amount, :currency, :description, keyword_init: true)

  class CapturingEpaycoClient
    attr_reader :payment_payload

    def create_payment_session(payload)
      @payment_payload = payload
      PaymentEngine::Result.success(
        data: { "data" => { "sessionId" => "session-123", "token" => "token-123" } }
      )
    end
  end

  setup do
    @provider = PaymentEngine::Provider.create!(
      code: "epayco-settings-#{SecureRandom.hex(4)}",
      name: "ePayco Settings",
      environment: "production",
      active: true,
      credentials: { "public_key" => "pk_test", "private_key" => "sk_test" },
      settings: { "country" => "CO" }
    )
  end

  test "provider settings include the persisted environment" do
    settings = PaymentEngine.provider_settings_for(@provider.code)

    assert_equal "production", settings[:environment]
    assert_equal "pk_test", settings[:public_key]
    assert_equal "CO", settings[:country]
  end

  test "epayco production provider creates a checkout in production mode" do
    result, payload, checkout = build_checkout(environment: "production")

    assert result.success?
    assert_equal false, payload[:test]
    assert_equal false, checkout["test"]
  end

  test "epayco sandbox provider keeps the checkout in test mode" do
    result, payload, checkout = build_checkout(environment: "sandbox")

    assert result.success?
    assert_equal true, payload[:test]
    assert_equal true, checkout["test"]
  end

  private

  def build_checkout(environment:)
    @provider.update!(environment: environment)
    settings = PaymentEngine.provider_settings_for(@provider.code)
    client = CapturingEpaycoClient.new
    provider = PaymentEngine::Providers::Epayco.new(settings: settings.merge(client: client))
    purchase = PurchaseStub.new(
      id: 123,
      amount: BigDecimal("14900.00"),
      currency: "COP",
      description: "Plan mensual"
    )

    result = provider.create_payment(purchase: purchase, payment: nil)
    checkout = result.data.is_a?(Hash) ? result.data[:checkout] : nil

    [ result, client.payment_payload, checkout ]
  end
end
