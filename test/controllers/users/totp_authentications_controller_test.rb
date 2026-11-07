# frozen_string_literal: true

require "test_helper"

class Users::TotpAuthenticationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user, @secret = create_totp_user(email: "totp-login-#{SecureRandom.hex(4)}@example.com")
  end

  test "does not validate TOTP without a pending password login" do
    post user_totp_authentication_path, params: { totp_code: totp_code(@secret) }

    assert_redirected_to new_user_session_path
    assert_nil session["warden.user.user.key"]
  end

  test "a valid TOTP code completes the login" do
    sign_in_with_password(@user)
    assert_redirected_to new_user_two_factor_authentication_path

    post user_totp_authentication_path, params: { totp_code: totp_code(@secret) }

    assert_redirected_to root_path
    follow_redirect!
    assert_equal @user.id, session["warden.user.user.key"].first.first
  end

  test "an invalid TOTP code does not create a session" do
    sign_in_with_password(@user)
    wrong_code = totp_code(TotpCredential.generate_secret)

    post user_totp_authentication_path, params: { totp_code: wrong_code }

    assert_redirected_to new_user_two_factor_authentication_path
    assert_nil session["warden.user.user.key"]
  end

  test "a TOTP code from another user is rejected" do
    other_user, other_secret = create_totp_user(email: "other-totp-login-#{SecureRandom.hex(4)}@example.com")
    sign_in_with_password(@user)

    post user_totp_authentication_path, params: { totp_code: totp_code(other_secret) }

    assert_redirected_to new_user_two_factor_authentication_path
    assert_nil session["warden.user.user.key"]
    assert other_user.totp_enabled?
  end

  test "reused TOTP codes do not create a second session" do
    travel_to(Time.zone.parse("2026-01-01 12:00:00")) do
      code = totp_code(@secret)

      sign_in_with_password(@user)
      post user_totp_authentication_path, params: { totp_code: code }
      assert_redirected_to root_path
      delete destroy_user_session_path

      sign_in_with_password(@user)
      post user_totp_authentication_path, params: { totp_code: code }

      assert_nil session["warden.user.user.key"]
    end
  end

  test "an expired TOTP code does not create a session" do
    travel_to(Time.zone.parse("2026-01-01 12:00:00")) do
      expired_code = totp_code(@secret, at: Time.current - 5.minutes)
      sign_in_with_password(@user)

      post user_totp_authentication_path, params: { totp_code: expired_code }

      assert_nil session["warden.user.user.key"]
    end
  end

  test "protected pages are not accessible while TOTP is pending" do
    sign_in_with_password(@user)

    get dashboard_path

    assert_redirected_to new_user_session_path
    assert_nil session["warden.user.user.key"]
  end

  test "the two factor page shows the TOTP form for a TOTP-only account" do
    sign_in_with_password(@user)
    follow_redirect!

    assert_response :success
    assert_select "[data-testid='totp-form']"
    assert_select "input[name='totp_code']"
    assert_select "[data-testid='security-key-form']", count: 0
  end

  test "the two factor page shows both methods when TOTP and WebAuthn are enabled" do
    @user.second_factor_webauthn_credentials.create!(
      external_id: SecureRandom.urlsafe_base64(16),
      name: "Llave",
      public_key: SecureRandom.base64(32),
      sign_count: 0,
      authentication_factor: :second_factor
    )
    sign_in_with_password(@user)
    follow_redirect!

    assert_response :success
    assert_select "[data-testid='totp-form']"
    assert_select "[data-testid='security-key-form']"
  end

  test "TOTP validation is rate limited" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    begin
      sign_in_with_password(@user)
      wrong_code = totp_code(TotpCredential.generate_secret)

      100.times do
        post user_totp_authentication_path, params: { totp_code: wrong_code }
      end

      post user_totp_authentication_path, params: { totp_code: wrong_code }

      assert_response :too_many_requests
      assert_nil session["warden.user.user.key"]
    ensure
      Rails.cache = original_cache
    end
  end

  test "TOTP parameters are filtered from logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter(totp_code: "123456", totp_secret: "SECRET", other: "visible")

    assert_equal "[FILTERED]", filtered[:totp_code]
    assert_equal "[FILTERED]", filtered[:totp_secret]
    assert_equal "visible", filtered[:other]
  end

  private

  def create_totp_user(email:)
    user = User.create!(
      name: "TOTP Login User",
      email: email,
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
    secret = TotpCredential.generate_secret
    user.create_totp_credential!(secret: secret)
    [ user, secret ]
  end

  def totp_code(secret, at: Time.current)
    ROTP::TOTP.new(secret).at(at).to_s
  end
end
