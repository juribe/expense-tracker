require "test_helper"
require "digest"

# Validates the ePayco webhook contract: signature is mandatory, states map
# to PaymentEngine records, and repeated notifications stay idempotent.
class PaymentEngineWebhooksTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @customer_id = "123456"
    @p_key = "test-p-key"

    @provider = PaymentEngine::Provider.find_or_create_by!(code: "epayco") do |p|
      p.name = "ePayco"
      p.active = true
      p.environment = "sandbox"
    end
    @provider.update!(
      credentials: {
        customer_id: @customer_id,
        p_key: @p_key
      },
      settings: {}
    )

    @membership_type = PaymentEngine::MembershipType.find_or_create_by!(code: "EPAYCO_TEST") { |mt| mt.name = "Epayco Test"; mt.status = "active" }
    @payment_option = PaymentEngine::PaymentOption.find_or_create_by!(membership_type: @membership_type, name: "Epayco Monthly") do |po|
      po.price = 14_900
      po.currency = "COP"
      po.mode = "recurring"
      po.interval = "month"
      po.interval_count = 1
      po.access_duration_count = 1
      po.access_duration_unit = "month"
      po.status = "active"
    end

    @owner = User.create!(email: "epayco-webhook-#{SecureRandom.hex(4)}@example.com", password: "password123", password_confirmation: "password123", confirmed_at: Time.current, financial_cycle_start_day: 1, debt_capacity_target_percentage: 50, debt_capacity_alert_percentage: 80)
    @purchase = PaymentEngine::Purchase.create!(owner: @owner, payment_option: @payment_option, amount: 14_900, currency: "COP", status: "pending")
    @payment = PaymentEngine::Payment.create!(purchase: @purchase, amount: @purchase.amount, currency: "COP", status: "pending", provider_code: "epayco")
    @purchase.update!(payment: @payment)

    # Provider adapters are memoized per process; start each test from the
    # credentials configured above instead of a previous test's instance.
    PaymentEngine.reset_providers!
  end

  test "rejected unauthorized notification keeps purchase pending" do
    post "/payment_engine/webhooks/epayco", params: webhook_payload.merge("x_signature" => "invalid")

    assert_response :unauthorized
    assert_equal "pending", @purchase.reload.status
    assert_equal "pending", @payment.reload.status
    assert_equal 0, PaymentEngine::WebhookEvent.count
  end

  test "unregistered provider notification is rejected and grants no access" do
    assert_no_difference [ "PaymentEngine::WebhookEvent.count", "PaymentEngine::Membership.count" ] do
      post "/payment_engine/webhooks/unregistered_provider", params: webhook_payload
    end

    assert_response :unauthorized
    assert_equal "pending", @purchase.reload.status
    assert_equal "pending", @payment.reload.status
  end

  test "notification without configured credentials is rejected" do
    @provider.update!(credentials: {}, settings: {})
    PaymentEngine.reset_providers!

    assert_no_difference [ "PaymentEngine::WebhookEvent.count", "PaymentEngine::Membership.count" ] do
      post "/payment_engine/webhooks/epayco", params: webhook_payload(customer_id: "", p_key: "")
    end

    assert_response :unauthorized
    assert_equal "pending", @purchase.reload.status
    assert_equal "pending", @payment.reload.status
  end

  test "rotating provider credentials invalidates the memoized adapter" do
    post "/payment_engine/webhooks/epayco", params: webhook_payload
    assert_response :ok

    @provider.update!(credentials: { customer_id: @customer_id, p_key: "rotated-p-key" })

    post "/payment_engine/webhooks/epayco", params: webhook_payload(p_key: "rotated-p-key")
    assert_response :ok

    post "/payment_engine/webhooks/epayco", params: webhook_payload
    assert_response :unauthorized
  end

  test "approved notification updates payment, purchase and membership" do
    post "/payment_engine/webhooks/epayco", params: webhook_payload

    assert_response :ok
    assert_equal "succeeded", @payment.reload.status
    assert_equal "paid", @purchase.reload.status
    assert PaymentEngine::Membership.where(owner: @owner, purchase: @purchase).exists?
  end

  test "repeated approved notification does not duplicate membership" do
    2.times { post "/payment_engine/webhooks/epayco", params: webhook_payload }

    assert_equal 1, PaymentEngine::Membership.where(owner: @owner, purchase: @purchase).count
    assert_equal "paid", @purchase.reload.status
  end

  test "refund notification revokes the membership granted by the purchase" do
    post "/payment_engine/webhooks/epayco", params: webhook_payload
    assert_response :ok
    membership = PaymentEngine::Membership.find_by!(purchase: @purchase)
    assert membership.active?

    post "/payment_engine/webhooks/epayco", params: refund_payload

    assert_response :ok
    assert_equal "refunded", @payment.reload.status
    assert_equal "refunded", @purchase.reload.status
    assert_equal "cancelled", membership.reload.status
    refute membership.access_granted?
  end

  test "refund keeps the membership when revoke_access_on_refund is disabled" do
    post "/payment_engine/webhooks/epayco", params: webhook_payload
    membership = PaymentEngine::Membership.find_by!(purchase: @purchase)
    previous = PaymentEngine.configuration.revoke_access_on_refund

    begin
      PaymentEngine.configuration.revoke_access_on_refund = false
      post "/payment_engine/webhooks/epayco", params: refund_payload
    ensure
      PaymentEngine.configuration.revoke_access_on_refund = previous
    end

    assert_response :ok
    assert_equal "refunded", @purchase.reload.status
    assert_equal "active", membership.reload.status
  end

  test "admin refund revokes the membership and marks the purchase refunded" do
    post "/payment_engine/webhooks/epayco", params: webhook_payload
    membership = PaymentEngine::Membership.find_by!(purchase: @purchase)

    result = PaymentEngine::Payments::Refund.call(payment: @payment, reason: "prueba")

    assert result.success?
    assert_equal "refunded", @payment.reload.status
    assert_equal "refunded", @purchase.reload.status
    assert_equal "cancelled", membership.reload.status
  end

  private

  def refund_payload
    webhook_payload.merge("x_cod_response" => "6", "x_response" => "Reversada")
  end

  def webhook_payload(customer_id: @customer_id, p_key: @p_key)
    signature = Digest::SHA256.hexdigest(
      [ customer_id, p_key, "ref-1", "txn-1", "14900.00", "COP" ].join("^")
    )
    {
      "x_ref_payco" => "ref-1",
      "x_transaction_id" => "txn-1",
      "x_amount" => "14900.00",
      "x_currency_code" => "COP",
      "x_id_factura" => @purchase.id,
      "x_claim_code" => "claim-1",
      "x_signature" => signature,
      "x_cod_response" => "1",
      "x_response" => "Aceptada",
      "x_transaction_date" => Time.current.strftime("%Y-%m-%d %H:%M:%S")
    }
  end
end
