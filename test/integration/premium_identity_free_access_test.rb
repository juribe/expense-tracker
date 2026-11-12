# frozen_string_literal: true

require "test_helper"

# An account created with an email that already used premium keeps free
# features but cannot obtain premium again.
class PremiumIdentityFreeAccessTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    @user = User.create!(
      name: "Returning Identity User",
      email: "returning_identity_#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    owner = User.create!(
      name: "Returning Identity Owner",
      email: "returning_identity_owner_#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    membership = PaymentEngine::Membership.create!(
      owner: owner,
      membership_type: membership_type,
      status: "active",
      source: "trial",
      starts_at: 1.month.ago,
      expires_at: 1.day.ago
    )
    PremiumIdentities::Protection.claim!(
      identity_type: "account_email",
      value: @user.email,
      user: owner,
      membership: membership
    )
  end

  test "the returning identity account can use the free part of the app" do
    sign_in @user

    get dashboard_path

    assert_response :success
    assert_select "[data-testid='membership-renewal-hero']"
  end

  test "the returning identity account sees the historical membership on the profile" do
    sign_in @user

    get profile_path

    assert_response :success
    assert_select ".plan-tag", text: /#{membership_type.name.upcase}/
  end

  test "the returning identity account cannot use premium features" do
    sign_in @user

    get gmail_connection_path

    assert_response :success
    assert_select "[data-testid='premium-locked']"
  end

  test "the returning identity account cannot start a new trial" do
    sign_in @user

    post start_trial_plans_path

    assert_redirected_to plans_path
    assert_match(/identidad/i, flash[:alert])
    assert_equal 0, PaymentEngine::Membership.where(owner: @user).count
  end

  private

  def membership_type
    @membership_type ||= PaymentEngine::MembershipType.create!(
      name: "Returning Identity Test",
      code: "RETURNING_#{SecureRandom.hex(6)}",
      status: "active"
    )
  end
end
