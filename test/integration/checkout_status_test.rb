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

PaymentEngine.register_provider(:verify_error_test, VerifyErrorProvider)
PaymentEngine.register_provider(:verify_cancelled_test, VerifyCancelledProvider)

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

  test "checkout result points the success redirect at the dashboard" do
    create_purchase(status: "pending")

    get checkout_result_plans_path

    assert_response :ok
    assert_includes response.body, 'data-checkout-success-url="/dashboard"'
  end

  test "an already paid checkout result redirects to the dashboard" do
    create_purchase(status: "paid")

    get checkout_result_plans_path

    assert_redirected_to dashboard_path
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
