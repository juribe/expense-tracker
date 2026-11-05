require "test_helper"

# Keeps the membership experience honest: no repeated free-trial offer and a
# membership status card plus an expiry banner the user sees once per day.
class PaymentEngineMembershipStatusTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @membership_type = PaymentEngine::MembershipType.find_or_create_by!(code: "BASIC") { |m| m.name = "Membresía Básica"; m.status = "active" }
    @monthly = PaymentEngine::PaymentOption.find_or_create_by!(membership_type: @membership_type, name: "Mensual") do |po|
      po.price = 14_900
      po.currency = "COP"
      po.mode = "recurring"
      po.interval = "month"
      po.interval_count = 1
      po.access_duration_count = 1
      po.access_duration_unit = "month"
      po.status = "active"
    end
    @user = User.create!(email: "membership-status-#{SecureRandom.hex(4)}@example.com", password: "password123", password_confirmation: "password123", confirmed_at: Time.current, financial_cycle_start_day: 1, debt_capacity_target_percentage: 50, debt_capacity_alert_percentage: 80)
    sign_in @user
  end

  test "plans page hides the free trial once the user already used it" do
    get plans_path
    assert_includes response.body, "Comenzar prueba gratis"

    PaymentEngine::Memberships::StartFreeTrial.call(owner: @user)

    get plans_path
    refute_includes response.body, "Comenzar prueba gratis"
  end

  test "profile shows the current membership" do
    PaymentEngine::Membership.create!(
      owner: @user,
      membership_type: @membership_type,
      status: "active",
      starts_at: Time.current,
      expires_at: Time.current + 1.month,
      source: "purchase"
    )

    get profile_path
    assert_response :success
    assert_includes response.body, "membership-status"
    assert_includes response.body, "Ver planes"
  end

  test "expiry banner shows once per day during the last five days" do
    PaymentEngine::Membership.create!(
      owner: @user,
      membership_type: @membership_type,
      status: "active",
      starts_at: Time.current,
      expires_at: Time.current + 4.days,
      source: "purchase"
    )

    get dashboard_path
    assert_response :success
    assert_includes response.body, "membership-expiry-banner"
    assert_includes response.body, "Renovar membresía"

    get plans_path
    refute_includes response.body, "membership-expiry-banner"
  end

  test "expiry banner is hidden before the last five days" do
    PaymentEngine::Membership.create!(
      owner: @user,
      membership_type: @membership_type,
      status: "active",
      starts_at: Time.current,
      expires_at: Time.current + 30.days,
      source: "purchase"
    )

    get dashboard_path
    assert_response :success
    refute_includes response.body, "membership-expiry-banner"
  end
end
