require "test_helper"

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
    payment = PaymentEngine::Payment.create!(
      purchase: purchase,
      amount: purchase.amount,
      currency: purchase.currency,
      status: status == "paid" ? "succeeded" : "pending",
      provider_code: "epayco"
    )
    purchase.update!(payment: payment)
    purchase
  end
end
