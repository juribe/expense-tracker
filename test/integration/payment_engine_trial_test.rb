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
  test "trial expires exactly the configured number of days after it starts" do
    PaymentEngine::Setting.current.update!(free_trial_duration_days: 30)

    post start_trial_plans_path

    membership = PaymentEngine::Membership.where(owner: @user, source: "trial").last
    assert membership.present?
    assert_equal 30, ((membership.expires_at - membership.starts_at) / 1.day).round(6)
    assert_in_delta 30.days.to_i, (membership.expires_at - membership.starts_at).to_i, 1
  end

  test "cannot start second trial" do
    PaymentEngine::Memberships::StartFreeTrial.call(owner: @user)
    post start_trial_plans_path
    assert_response :redirect
    assert_equal 1, PaymentEngine::Membership.where(owner: @user, source: "trial").count
  end

  test "cannot start a second trial after the first expired" do
    PaymentEngine::Memberships::StartFreeTrial.call(owner: @user)
    PaymentEngine::Membership.where(owner: @user, source: "trial")
                             .update_all(status: "expired", expires_at: 1.day.ago)

    post start_trial_plans_path

    assert_redirected_to plans_path
    assert_equal "El usuario ya utilizó su prueba gratuita", flash[:alert]
    assert_equal 1, PaymentEngine::Membership.where(owner: @user, source: "trial").count
  end
  test "access policy premium true during trial" do
    PaymentEngine::Memberships::StartFreeTrial.call(owner: @user)
    assert PaymentEngine::AccessPolicy.premium_access?(@user)
  end
end
