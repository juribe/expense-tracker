require "test_helper"

class PaymentEngineAdminTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  setup do
    @user = User.create!(email: "user@example.com", password: "password123", password_confirmation: "password123", confirmed_at: Time.current, financial_cycle_start_day: 1, debt_capacity_target_percentage: 50, debt_capacity_alert_percentage: 80)
    @admin = User.create!(email: "admin@example.com", password: "password123", password_confirmation: "password123", admin: true, confirmed_at: Time.current, financial_cycle_start_day: 1, debt_capacity_target_percentage: 50, debt_capacity_alert_percentage: 80)
  end

  test "unauthenticated redirected to login" do
    get "/payment_engine/admin"
    assert_response :redirect
  end

  test "normal user redirected to the dashboard" do
    sign_in @user
    get "/payment_engine/admin"

    assert_redirected_to "/dashboard"
    assert_equal I18n.t("errors.not_authorized"), flash[:alert]
  end

  test "normal user redirected from a nested admin route" do
    sign_in @user
    get "/payment_engine/admin/payment_options"

    assert_redirected_to "/dashboard"
    assert_equal I18n.t("errors.not_authorized"), flash[:alert]
  end

  test "admin can access dashboard" do
    sign_in @admin
    get "/payment_engine/admin"
    assert_response :success
  end

  test "admin can access all admin routes" do
    sign_in @admin
    [ "/payment_engine/admin/membership_types", "/payment_engine/admin/payment_options", "/payment_engine/admin/memberships", "/payment_engine/admin/subscriptions", "/payment_engine/admin/purchases", "/payment_engine/admin/payments", "/payment_engine/admin/providers", "/payment_engine/admin/webhook_events", "/payment_engine/admin/settings" ].each do |path|
      get path
      assert_response :success, "Failed for #{path}"
    end
  end
end
