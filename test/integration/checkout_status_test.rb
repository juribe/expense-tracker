require "test_helper"

class VerifyErrorProvider < PaymentEngine::Providers::Base
  def fetch_payment(provider_transaction_id:)
    PaymentEngine::Result.success(
      data: { "success" => false, "textResponse" => "referencePayco invalid" }
    )
  end
end

class VerifyCancelledProvider < PaymentEngine::Providers::Base
  def fetch_payment(provider_transaction_id:)
    PaymentEngine::Result.success(
      data: { "success" => true, "data" => { "status" => "Cancelada", "bill" => provider_transaction_id } }
    )
  end
end

class VerifyApprovedProvider < PaymentEngine::Providers::Base
  class << self
    attr_accessor :data
  end

  def fetch_payment(provider_transaction_id:)
    PaymentEngine::Result.success(data: { "success" => true, "data" => self.class.data })
  end
end

PaymentEngine.register_provider(:verify_error_test, VerifyErrorProvider)
PaymentEngine.register_provider(:verify_cancelled_test, VerifyCancelledProvider)
PaymentEngine.register_provider(:verify_approved_test, VerifyApprovedProvider)

# The checkout result page polls this endpoint; it must return normalized
# statuses and treat an already-paid purchase as a successful payment.
class CheckoutStatusTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @owner = User.create!(
      email: "checkout-status-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current,
      financial_cycle_start_day: 1,
      debt_capacity_target_percentage: 50,
      debt_capacity_alert_percentage: 80
    )
    sign_in @owner

    membership_type = PaymentEngine::MembershipType.create!(
      code: "CHECKOUT_STATUS",
      name: "Checkout Status",
      status: "active"
    )
    @option = PaymentEngine::PaymentOption.create!(
      membership_type: membership_type,
      name: "Mensual Status",
      price: 14_900,
      currency: "COP",
      mode: "recurring",
      interval: "month",
      interval_count: 1,
      access_duration_count: 1,
      access_duration_unit: "month",
      status: "active"
    )
  end

  test "returns succeeded for an already paid purchase" do
    purchase = create_purchase(status: "paid")

    get checkout_status_plans_path

    assert_response :ok
    assert_equal "succeeded", JSON.parse(response.body)["status"]
    assert_equal purchase.id, JSON.parse(response.body)["purchase_id"]
  end

  test "returns pending for a pending purchase" do
    create_purchase(status: "pending")

    get checkout_status_plans_path

    assert_response :ok
    assert_equal "pending", JSON.parse(response.body)["status"]
  end

  test "returns failed for a failed purchase even when a provider ref is present" do
    create_purchase(status: "failed")

    get checkout_status_plans_path(ref_payco: "6aea42dbc7396940e5177291")

    assert_response :ok
    assert_equal "failed", JSON.parse(response.body)["status"]
  end

  test "checkout result stays on the confirmation page for a pending purchase" do
    create_purchase(status: "pending")

    get checkout_result_plans_path

    assert_response :ok
    assert_select ".checkout-result"
    assert_select "[data-checkout-status]", text: "pending"
    assert_select "[data-checkout-success-url]", count: 0
  end

  test "an already paid checkout result renders the confirmation page instead of redirecting" do
    create_purchase(status: "paid")

    get checkout_result_plans_path

    assert_response :ok
    assert_select ".checkout-result"
    assert_select "[data-checkout-status]", text: "succeeded"
  end

  test "verification treats a provider error as failure instead of pending" do
    purchase = create_purchase(status: "pending")

    result = PaymentEngine::Payments::Verify.call(
      provider: "verify_error_test",
      reference: "invalid-ref",
      purchase: purchase
    )

    refute result.success?
    assert_equal :provider_rejected_query, result.code
    assert_equal "pending", purchase.reload.status
  end

  test "verification marks a cancelled transaction as failed" do
    purchase = create_purchase(status: "pending")

    result = PaymentEngine::Payments::Verify.call(
      provider: "verify_cancelled_test",
      reference: purchase.id.to_s,
      purchase: purchase
    )

    assert result.success?
    assert_equal "failed", result.data[:state]
    assert_equal "failed", purchase.reload.status
  end

  test "verification rejects a transaction for a different invoice" do
    purchase = create_purchase(status: "pending")
    VerifyApprovedProvider.data = provider_transaction(purchase, invoice: purchase.id + 1)

    result = verify_purchase(purchase, reference: "ref-approved")

    refute result.success?
    assert_equal :invoice_mismatch, result.code
    assert_equal "pending", purchase.reload.status
    assert_equal 0, PaymentEngine::Membership.where(purchase: purchase).count
  end

  test "verification rejects a transaction with a different amount" do
    purchase = create_purchase(status: "pending")
    VerifyApprovedProvider.data = provider_transaction(purchase, amount: "100.00")

    result = verify_purchase(purchase, reference: "ref-approved")

    refute result.success?
    assert_equal :amount_mismatch, result.code
    assert_equal "pending", purchase.reload.status
  end

  test "verification rejects a transaction with a different currency" do
    purchase = create_purchase(status: "pending")
    VerifyApprovedProvider.data = provider_transaction(purchase, currency: "USD")

    result = verify_purchase(purchase, reference: "ref-approved")

    refute result.success?
    assert_equal :currency_mismatch, result.code
    assert_equal "pending", purchase.reload.status
  end

  test "verification rejects a reference already stored on another payment" do
    used = create_purchase(status: "paid")
    used.payment.update!(external_reference: "ref-used")
    purchase = create_purchase(status: "pending")
    VerifyApprovedProvider.data = provider_transaction(purchase)

    result = verify_purchase(purchase, reference: "ref-used")

    refute result.success?
    assert_equal :reference_already_used, result.code
    assert_equal "pending", purchase.reload.status
    assert_equal 0, PaymentEngine::Membership.where(purchase: purchase).count
  end

  test "verification settles a matching transaction" do
    purchase = create_purchase(status: "pending")
    VerifyApprovedProvider.data = provider_transaction(purchase)

    result = verify_purchase(purchase, reference: "ref-new")

    assert result.success?
    assert_equal "succeeded", result.data[:state]
    assert_equal "paid", purchase.reload.status
    assert_equal "ref-new", purchase.payment.reload.external_reference
    assert PaymentEngine::Membership.where(owner: @owner, purchase: purchase).exists?
  end

  test "verification rejects a response that cannot be bound to the purchase" do
    purchase = create_purchase(status: "pending")
    VerifyApprovedProvider.data = { "x_cod_response" => "1", "x_response" => "Aceptada" }

    result = verify_purchase(purchase, reference: "ref-unbound")

    refute result.success?
    assert_equal :unverifiable_transaction, result.code
    assert_equal "pending", purchase.reload.status
  end

  test "database rejects duplicate provider references" do
    first = create_purchase(status: "paid")
    first.payment.update!(external_reference: "dup-ref")
    second = create_purchase(status: "pending")

    assert_raises(ActiveRecord::RecordNotUnique) do
      second.payment.update_column(:external_reference, "dup-ref")
    end
  end

  test "webhook maps a cancelled response to rejected" do
    handler = PaymentEngine::Providers::Epayco::WebhookHandler.new(
      settings: { customer_id: "customer", p_key: "key" }
    )

    result = handler.parse(
      payload: {
        "x_cod_response" => "0",
        "x_response" => "Cancelada",
        "x_ref_payco" => "392216452",
        "x_transaction_id" => "48772185953887",
        "x_id_factura" => "33",
        "x_amount" => "14900.00",
        "x_currency_code" => "COP"
      }
    )

    assert result.success?
    assert_equal "payment.rejected", result.data[:event_type]
  end

  test "requires authentication" do
    sign_out @owner

    get checkout_status_plans_path

    assert_response :redirect
  end

  private

  def teardown
    VerifyApprovedProvider.data = nil
  end

  def verify_purchase(purchase, reference:)
    PaymentEngine::Payments::Verify.call(
      provider: "verify_approved_test",
      reference: reference,
      purchase: purchase,
      payment: purchase.payment
    )
  end

  def provider_transaction(purchase, invoice: purchase.id, amount: "14900.00", currency: "COP")
    {
      "x_cod_response" => "1",
      "x_response" => "Aceptada",
      "x_ref_payco" => "ref-approved",
      "x_transaction_id" => "txn-approved",
      "x_id_factura" => invoice.to_s,
      "x_amount" => amount,
      "x_currency_code" => currency
    }
  end

  def create_purchase(status:)
    purchase = PaymentEngine::Purchase.create!(
      owner: @owner,
      payment_option: @option,
      amount: @option.price,
      currency: @option.currency,
      status: status
    )
    payment_status = case status
    when "paid" then "succeeded"
    when "failed" then "failed"
    else "pending"
    end
    payment = PaymentEngine::Payment.create!(
      purchase: purchase,
      amount: purchase.amount,
      currency: purchase.currency,
      status: payment_status,
      provider_code: "epayco"
    )
    purchase.update!(payment: payment)
    purchase
  end
end
