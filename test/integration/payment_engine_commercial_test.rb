require "test_helper"
class PaymentEngineCommercialTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  setup do
    @admin = User.create!(email: "admincomm@example.com", password: "password123", password_confirmation: "password123", admin: true, confirmed_at: Time.current, financial_cycle_start_day: 1, debt_capacity_target_percentage: 50, debt_capacity_alert_percentage: 80)
    sign_in @admin
  end
  test "admin can view commercial settings" do
    get "/payment_engine/admin/settings/commercial"
    assert_response :success
  end
  test "update duration" do
    patch "/payment_engine/admin/settings/commercial", params: { setting: { free_trial_duration_days: 30 } }
    assert_response :redirect
    assert_equal 30, PaymentEngine::Setting.current.free_trial_duration_days
    assert_equal 30, PaymentEngine::Configuration.free_trial_duration_days
  end
  test "defaults" do
    s = PaymentEngine::Setting.current
    assert_equal true, s.payments_enabled
    assert_equal 60, s.free_trial_duration_days rescue nil
  end
  test "normal user redirected to the dashboard" do
    sign_out @admin
    user = User.create!(email: "ucomm@example.com", password: "password123", password_confirmation: "password123", confirmed_at: Time.current, financial_cycle_start_day: 1, debt_capacity_target_percentage: 50, debt_capacity_alert_percentage: 80)
    sign_in user
    get "/payment_engine/admin/settings/commercial"

    assert_redirected_to "/dashboard"
    assert_equal I18n.t("errors.not_authorized"), flash[:alert]
  end
end
