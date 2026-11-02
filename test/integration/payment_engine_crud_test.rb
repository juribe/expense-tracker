require "test_helper"
class PaymentEngineCrudTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  setup do
    @admin = User.create!(email: "admin2@example.com", password: "password123", password_confirmation: "password123", admin: true, confirmed_at: Time.current, financial_cycle_start_day: 1, debt_capacity_target_percentage: 50, debt_capacity_alert_percentage: 80)
    sign_in @admin
  end
  test "create membership type" do
    post "/payment_engine/admin/membership_types", params: { membership_type: { name: "Premium", code: "PREM", status: "active", position: 1 } }
    assert_response :redirect
    assert PaymentEngine::MembershipType.find_by(code: "PREM")
  end
  test "grant membership" do
    mt = PaymentEngine::MembershipType.create!(name: "Basic", code: "BASIC", status: "active")
    user = User.create!(email: "u2@example.com", password: "password123", password_confirmation: "password123", confirmed_at: Time.current, financial_cycle_start_day: 1, debt_capacity_target_percentage: 50, debt_capacity_alert_percentage: 80)
    post "/payment_engine/admin/memberships", params: { owner_type: "User", owner_id: user.id, membership: { membership_type_id: mt.id, starts_at: Time.current.strftime("%Y-%m-%dT%H:%M") }, reason: "test" }
    assert_response :redirect
    assert PaymentEngine::Membership.where(owner: user).exists?
  end
  test "webhook idempotency" do
    post "/payment_engine/webhooks/stripe", params: { id: "evt1", type: "payment.succeeded" }
    assert_response :ok
    assert_equal 1, PaymentEngine::WebhookEvent.where(external_id: "evt1").count
    post "/payment_engine/webhooks/stripe", params: { id: "evt1", type: "payment.succeeded" }
    assert_response :ok
    assert_equal 1, PaymentEngine::WebhookEvent.where(external_id: "evt1").count
  end
end
