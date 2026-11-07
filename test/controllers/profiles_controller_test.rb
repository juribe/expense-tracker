# frozen_string_literal: true

require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = create_user(email: "profile-communications-#{SecureRandom.hex(4)}@example.com")
    sign_in @user
  end

  test "requires authentication to update communications" do
    sign_out :user

    assert_no_difference -> { UserConsent.count } do
      patch profile_communications_path, params: { user: { marketing_consent: "1" } }
    end

    assert_redirected_to new_user_session_path
  end

  test "grants marketing consent from account settings" do
    assert_difference -> { @user.user_consents.marketing.count }, 1 do
      patch profile_communications_path, params: { user: { marketing_consent: "1" } }
    end

    assert_redirected_to profile_path
    consent = latest_marketing_consent(@user)

    assert consent.granted?
    assert consent.occurred_at.present?
  end

  test "withdraws marketing consent from account settings" do
    previous = create_marketing_consent(@user, granted: true, occurred_at: 1.hour.ago)

    assert_difference -> { @user.user_consents.marketing.count }, 1 do
      patch profile_communications_path, params: { user: { marketing_consent: "0" } }
    end

    assert_redirected_to profile_path
    consent = latest_marketing_consent(@user)

    refute consent.granted?
    assert consent.occurred_at >= previous.occurred_at
  end

  test "does not alter another user's marketing consent" do
    other_user = create_user(email: "other-communications-#{SecureRandom.hex(4)}@example.com")
    create_marketing_consent(other_user, granted: true)

    patch profile_communications_path, params: { user: { marketing_consent: "0" } }

    refute latest_marketing_consent(@user).granted?
    assert latest_marketing_consent(other_user).granted?
  end

  test "shows the marketing consent status and form on the profile" do
    get profile_path

    assert_response :success
    assert_select "[data-testid='marketing-consent-card']"
    assert_select "form[action='#{profile_communications_path}']"
    assert_select "input#user_marketing_consent[type='checkbox']"
    assert_select "input#user_marketing_consent[checked]", count: 0

    create_marketing_consent(@user, granted: true)

    get profile_path

    assert_select "input#user_marketing_consent[checked]", count: 1
  end

  private

  def create_user(email:)
    User.create!(
      name: "Profile User",
      email: email,
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
  end

  def create_marketing_consent(user, granted:, occurred_at: Time.current)
    user.user_consents.create!(
      consent_type: "marketing",
      granted: granted,
      occurred_at: occurred_at
    )
  end

  def latest_marketing_consent(user)
    user.user_consents.marketing.order(occurred_at: :desc, created_at: :desc).first
  end
end
