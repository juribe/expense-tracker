require "test_helper"
require "digest"

class ProvidersTest < PaymentEngineTestCase
  test "registry resolves registered adapters and rejects unknown ones" do
    assert_instance_of PaymentEngine::Providers::Fake, PaymentEngine.provider(:fake)
    assert PaymentEngine.provider?(:epayco)
    assert_raises(PaymentEngine::UnknownProviderError) { PaymentEngine.provider(:unknown) }
  end

  test "registering a class that does not inherit from Base is rejected" do
    assert_raises(ArgumentError) { PaymentEngine.register_provider(:invalid, String) }
  end

  test "the default provider is used when no provider is given" do
    PaymentEngine.configure { |config| config.default_provider = :fake }

    assert_equal :fake, PaymentEngine.provider.name
  end

  test "capabilities are declared explicitly" do
    fake = PaymentEngine.provider(:fake)
    limited = PaymentEngine.provider(:limited)

    assert fake.supports?(:recurring_payments)
    assert fake.supports?(:refunds)
    refute limited.supports?(:recurring_payments)
  end

  test "unsupported operations return a controlled error" do
    result = PaymentEngine.provider(:limited).create_subscription(subscription: nil)

    assert_failure(result, code: :unsupported_operation)
  end

  test "ePayco verifies the documented confirmation signature" do
    handler = PaymentEngine::Providers::Epayco::WebhookHandler.new(
      settings: { customer_id: "123456", p_key: "test-p-key" }
    )
    payload = {
      "x_ref_payco" => "ref-1",
      "x_transaction_id" => "txn-1",
      "x_amount" => "19900.00",
      "x_currency_code" => "COP"
    }
    signature = Digest::SHA256.hexdigest(
      [ "123456", "test-p-key", "ref-1", "txn-1", "19900.00", "COP" ].join("^")
    )

    assert handler.verify(payload: payload.merge("x_signature" => signature))
    refute handler.verify(payload: payload.merge("x_signature" => "invalid"))
    refute handler.verify(payload: payload)
  end

  test "ePayco translates approved, rejected and refunded states" do
    handler = PaymentEngine::Providers::Epayco::WebhookHandler.new(
      settings: { customer_id: "123456", p_key: "test-p-key" }
    )
    base = {
      "x_ref_payco" => "ref-1",
      "x_transaction_id" => "txn-1",
      "x_amount" => "19900.00",
      "x_currency_code" => "COP",
      "x_id_factura" => "42",
      "x_transaction_date" => "2026-01-15 10:00"
    }

    approved = assert_success(handler.parse(payload: base.merge("x_cod_response" => "1", "x_response" => "Aceptada")))
    rejected = assert_success(handler.parse(payload: base.merge("x_cod_response" => "2", "x_response" => "Rechazada")))
    refunded = assert_success(handler.parse(payload: base.merge("x_cod_response" => "6", "x_response" => "Reversada")))

    assert_equal "payment.approved", approved.data[:event_type]
    assert_equal 42, approved.data[:purchase_id]
    assert_equal 19_900, approved.data[:amount]
    assert_equal "payment.rejected", rejected.data[:event_type]
    assert_equal "payment.refunded", refunded.data[:event_type]
  end

  test "ePayco delegates payment creation to its configured client" do
    client = Object.new
    def client.create_payment_session(payload)
      PaymentEngine::Result.success(data: { sessionId: "session-1", payload: payload })
    end

    adapter = PaymentEngine::Providers::Epayco.new(settings: { client: client })
    purchase = create_purchase(owner: create_owner)
    payment = create_payment(purchase: purchase)

    result = adapter.create_payment(purchase: purchase, payment: payment)

    assert_success(result)
    assert_equal "session-1", result.data[:checkout][:sessionId]
  end

  test "ePayCo subscription creation requires a configured plan" do
    client = Object.new
    adapter = PaymentEngine::Providers::Epayco.new(settings: { client: client })
    subscription = create_subscription(membership: create_membership(owner: create_owner))

    assert_failure(adapter.create_subscription(subscription: subscription), code: :missing_plan)
  end
end
