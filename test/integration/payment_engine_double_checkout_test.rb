require "test_helper"

# Verifies the double-intent guard added to plans#create_checkout and the
# scheduled reconciliation that closes abandoned purchases.
class PaymentEngineDoubleCheckoutTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @membership_type = PaymentEngine::MembershipType.find_or_create_by!(code: "BASIC") { |m| m.name = "Membresía Básica"; m.status = "active" }
    @option = PaymentEngine::PaymentOption.find_or_create_by!(membership_type: @membership_type, name: "Mensual") do |po|
      po.price = 14_900
      po.currency = "COP"
      po.mode = "recurring"
      po.interval = "month"
      po.interval_count = 1
      po.access_duration_count = 1
      po.access_duration_unit = "month"
      po.status = "active"
    end

    @user = User.create!(
      email: "epayco-reconcile-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current,
      financial_cycle_start_day: 1,
      debt_capacity_target_percentage: 50,
      debt_capacity_alert_percentage: 80
    )
    sign_in @user
  end

  test "reuses the same pending purchase instead of creating a second one" do
    post "/plans/checkout", params: { payment_option_id: @option.id, method: "card" }
    assert_response :redirect

    post "/plans/checkout", params: { payment_option_id: @option.id, method: "card" }
    assert_response :redirect

    assert_equal 1, PaymentEngine::Purchase.where(owner: @user, payment_option: @option).where(status: "pending").count
  end

  test "abandoned pending purchase is cancelled by the reconciliation job" do
    travel_to PaymentEngine::ReconcilePaymentsJob::ABANDONMENT_WINDOW_MINUTES.minutes.ago - 1.minute do
      post "/plans/checkout", params: { payment_option_id: @option.id, method: "card" }
      assert_response :redirect
    end

    PaymentEngine::ReconcilePaymentsJob.perform_now

    purchase = PaymentEngine::Purchase.find_by(owner: @user, payment_option: @option)
    assert_equal "cancelled", purchase.status
  end
end