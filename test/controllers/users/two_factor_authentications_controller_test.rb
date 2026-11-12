# frozen_string_literal: true

require "test_helper"

class Users::TwoFactorAuthenticationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Two Factor User",
      email: "two-factor-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
    @client = webauthn_client
    sign_in @user
    register_second_factor_credential(@user, client: @client)
    delete destroy_user_session_path
  end

  test "the two factor page renders a security key form and a recovery code form" do
    sign_in_with_password(@user)
    assert_redirected_to new_user_two_factor_authentication_path

    get new_user_two_factor_authentication_path

    assert_response :success
    assert_select "h1", text: I18n.t("security.two_factor.title", default: "Verificación en dos pasos")
    assert_select "[data-testid='security-key-form']"
    assert_select "[data-testid='totp-form']", count: 0
    assert_select "input[name='recovery_code']"
    assert_nil session["warden.user.user.key"]
  end

  test "a valid security key completes the sign in" do
    sign_in_with_password(@user)
    assert_redirected_to new_user_two_factor_authentication_path

    complete_second_factor(client: @client)

    assert_redirected_to root_path
    follow_redirect!
    assert_equal @user.id, session["warden.user.user.key"].first.first
  end

  test "a first-factor passkey cannot satisfy the second factor" do
    passkey_client = new_webauthn_client
    recovery_code = RecoveryCode.generate_for(@user).first
    sign_in @user
    register_passkey(
      @user,
      name: "Mi passkey",
      client: passkey_client,
      extra_params: { recovery_code: recovery_code }
    )
    delete destroy_user_session_path

    sign_in_with_password(@user)
    post user_security_key_authentication_options_path
    options = JSON.parse(response.body)
    credential = passkey_client.get(
      challenge: options.fetch("challenge"),
      rp_id: "localhost",
      user_verified: false,
      user_handle: webauthn_user_handle(@user)
    )

    post user_two_factor_authentication_path, params: { public_key_credential: credential.to_json }

    assert_nil session["warden.user.user.key"]
    refute_equal root_url, response.location if response.redirect?
  end

  test "an invalid security key does not complete the sign in" do
    sign_in_with_password(@user)
    post user_security_key_authentication_options_path
    options = JSON.parse(response.body)
    wrong_credential = @client.get(
      challenge: WebAuthn.configuration.encoder.encode(SecureRandom.random_bytes(32)),
      rp_id: "localhost",
      user_verified: false
    )

    post user_two_factor_authentication_path,
         params: { public_key_credential: wrong_credential.to_json }

    assert_redirected_to new_user_two_factor_authentication_path
    assert_nil session["warden.user.user.key"]
  end

  test "a reused security key challenge does not complete the sign in" do
    sign_in_with_password(@user)
    credential = complete_second_factor(client: @client)
    assert_redirected_to root_path
    delete destroy_user_session_path

    sign_in_with_password(@user)
    post user_two_factor_authentication_path,
         params: { public_key_credential: credential.to_json }

    assert_nil session["warden.user.user.key"]
  end

  test "an expired security key challenge does not complete the sign in" do
    sign_in_with_password(@user)
    post user_security_key_authentication_options_path
    options = JSON.parse(response.body)

    travel 6.minutes do
      credential = @client.get(challenge: options.fetch("challenge"), rp_id: "localhost",
                               user_verified: false)

      post user_two_factor_authentication_path,
           params: { public_key_credential: credential.to_json }
    end

    assert_nil session["warden.user.user.key"]
  end

  test "a canceled ceremony does not complete the sign in" do
    sign_in_with_password(@user)

    post user_two_factor_authentication_path, params: { public_key_credential: "" }

    assert_nil session["warden.user.user.key"]
  end

  test "the second factor cannot be completed without starting the sign in" do
    post user_two_factor_authentication_path, params: { public_key_credential: "{}" }

    assert_redirected_to new_user_session_path
    assert_nil session["warden.user.user.key"]
  end

  test "a TOTP-only account sees the TOTP form and not the security key form" do
    user = User.create!(
      name: "TOTP Only User",
      email: "totp-only-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
    user.create_totp_credential!(secret: TotpCredential.generate_secret)

    sign_in_with_password(user)
    follow_redirect!

    assert_response :success
    assert_select "[data-testid='totp-form']"
    assert_select "input[name='totp_code']"
    assert_select "[data-testid='security-key-form']", count: 0
  end

  test "an account with TOTP and WebAuthn sees both second factor forms" do
    @user.create_totp_credential!(secret: TotpCredential.generate_secret)

    sign_in_with_password(@user)
    follow_redirect!

    assert_response :success
    assert_select "[data-testid='security-key-form']"
    assert_select "[data-testid='totp-form']"
  end
end
