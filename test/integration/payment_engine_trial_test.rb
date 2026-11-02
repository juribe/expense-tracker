require "test_helper"
class PaymentEngineTrialTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  setup do
    PaymentEngine::MembershipType.find_or_create_by!(code: "BASIC") { |m| m.name = "Membresía Básica"; m.status = "active" }
    @user = User.create!(email: "trialuser@example.com", password: "password123", password_confirmation: "password123", confirmed_at: Time.current, financial_cycle_start_day: 1, debt_capacity_target_percentage: 50, debt_capacity_alert_percentage: 80)
    sign_in @user
  end
  test "start trial creates membership source trial" do
    post start_trial_plans_path
    assert_response :redirect
    m = PaymentEngine::Membership.where(owner: @user, source: "trial").last
    assert m.present?
    assert m.active?
    assert_nil m.purchase_id
    assert_nil m.subscription_id
  end
  test "cannot start second trial" do
    PaymentEngine::Memberships::StartFreeTrial.call(owner: @user)
    post start_trial_plans_path
    assert_response :redirect
    assert_equal 1, PaymentEngine::Membership.where(owner: @user, source: "trial").count
  end
  test "access policy premium true during trial" do
    PaymentEngine::Memberships::StartFreeTrial.call(owner: @user)
    assert PaymentEngine::AccessPolicy.premium_access?(@user)
  end
end
