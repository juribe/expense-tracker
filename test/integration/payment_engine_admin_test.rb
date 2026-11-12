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
    [ "/payment_engine/admin/membership_types", "/payment_engine/admin/payment_options", "/payment_engine/admin/memberships", "/payment_engine/admin/subscriptions", "/payment_engine/admin/purchases", "/payment_engine/admin/payments", "/payment_engine/admin/providers", "/payment_engine/admin/webhook_events", "/payment_engine/admin/settings", "/payment_engine/admin/premium_identities" ].each do |path|
      get path
      assert_response :success, "Failed for #{path}"
    end
  end

  test "normal user cannot access premium identities" do
    sign_in @user

    get "/payment_engine/admin/premium_identities"

    assert_redirected_to "/dashboard"
  end

  test "admin can release a premium identity with an audit entry" do
    identity = PremiumIdentities::Protection.claim!(
      identity_type: "account_email",
      value: "admin-release@example.com",
      user: @user
    )
    sign_in @admin

    get "/payment_engine/admin/premium_identities/#{identity.id}"
    assert_response :success

    post "/payment_engine/admin/premium_identities/#{identity.id}/release",
         params: { reason: "Verified support request" }

    assert_redirected_to "/payment_engine/admin/premium_identities/#{identity.id}"
    assert identity.reload.released?
    audit = PaymentEngine::AuditLog.where(action: "premium_identity.released").last
    assert audit
    assert_equal @admin.id.to_s, audit.actor_id
    assert_equal "Verified support request", audit.reason
  end
end
