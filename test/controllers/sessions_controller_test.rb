# frozen_string_literal: true

require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Test User",
      email: "sessions_test@example.com",
      password: "password123"
    )
  end

  test "DELETE /users/sign_out signs out a signed-in user" do
    sign_in @user
    delete destroy_user_session_path
    assert_response :redirect
    get dashboard_path
    assert_redirected_to new_user_session_path
  end

  test "GET /users/sign_out signs out a signed-in user without JavaScript" do
    sign_in @user
    get user_session_sign_out_get_path
    assert_response :redirect
    get dashboard_path
    assert_redirected_to new_user_session_path
  end

  test "GET /users/sign_out does not raise a routing error" do
    get "/users/sign_out"
    assert_response :redirect
  end

  test "the sign in page keeps the password form and offers passkey authentication" do
    get new_user_session_path

    assert_response :success
    assert_select "#user_email"
    assert_select "#user_password"
    assert_select "[data-testid='passkey-login']"
    assert_select "[data-testid='auth-divider']", text: /O continúa de otra manera/
    assert_select "script[type='module'][src*='devise/webauthn']"
    assert_select "script[src*='webauthn_ui']"
  end

  test "sign in with a valid passkey creates the session" do
    user = create_confirmed_user(email: "passkey-login@example.com")
    client = webauthn_client
    sign_in user
    register_passkey(user, client: client)
    delete destroy_user_session_path

    login_with_passkey(user, client: client)

    assert_redirected_to root_path
    follow_redirect!
    assert_equal user.id, session["warden.user.user.key"].first.first
  end

  test "sign in with an unknown credential does not create the session" do
    user = create_confirmed_user(email: "unknown-passkey@example.com")
    user.ensure_webauthn_id!
    client = new_webauthn_client
    client.create(challenge: WebAuthn.configuration.encoder.encode(SecureRandom.random_bytes(32)),
                  rp_id: "localhost", user_verified: true)

    post user_passkey_authentication_options_path
    options = JSON.parse(response.body)
    credential = client.get(challenge: options.fetch("challenge"), rp_id: "localhost",
                            user_verified: true, user_handle: webauthn_user_handle(user))
    post user_session_path, params: { public_key_credential: credential.to_json }

    assert_redirected_to new_user_session_path
    assert_nil session["warden.user.user.key"]
  end

  test "sign in with a credential that belongs to another user does not create the session" do
    owner = create_confirmed_user(email: "passkey-owner@example.com")
    other = create_confirmed_user(email: "passkey-other@example.com")
    other.ensure_webauthn_id!
    client = webauthn_client
    sign_in owner
    register_passkey(owner, client: client)
    delete destroy_user_session_path

    post user_passkey_authentication_options_path
    options = JSON.parse(response.body)
    credential = client.get(challenge: options.fetch("challenge"), rp_id: "localhost",
                            user_verified: true, user_handle: webauthn_user_handle(other))
    post user_session_path, params: { public_key_credential: credential.to_json }

    assert_redirected_to new_user_session_path
    assert_nil session["warden.user.user.key"]
  end

  test "an authentication challenge cannot be reused" do
    user = create_confirmed_user(email: "replay-passkey@example.com")
    client = webauthn_client
    sign_in user
    register_passkey(user, client: client)
    delete destroy_user_session_path

    credential = login_with_passkey(user, client: client)
    assert_redirected_to root_path
    delete destroy_user_session_path

    post user_session_path, params: { public_key_credential: credential.to_json }

    assert_nil session["warden.user.user.key"]
  end

  test "an expired authentication challenge does not create the session" do
    user = create_confirmed_user(email: "expired-passkey@example.com")
    client = webauthn_client
    sign_in user
    register_passkey(user, client: client)
    delete destroy_user_session_path

    post user_passkey_authentication_options_path
    options = JSON.parse(response.body)

    travel 6.minutes do
      credential = client.get(challenge: options.fetch("challenge"), rp_id: "localhost",
                              user_verified: true, user_handle: webauthn_user_handle(user))
      post user_session_path, params: { public_key_credential: credential.to_json }
    end

    assert_nil session["warden.user.user.key"]
  end

  test "an inactive account cannot sign in with a passkey" do
    user = create_confirmed_user(email: "inactive-passkey@example.com")
    client = webauthn_client
    sign_in user
    register_passkey(user, client: client)
    delete destroy_user_session_path
    user.update_column(:confirmed_at, nil)

    login_with_passkey(user, client: client)

    assert_nil session["warden.user.user.key"]
  end

  test "a user with passkeys but no second factor keeps the traditional password login" do
    user = create_confirmed_user(email: "password-with-passkey@example.com")
    sign_in user
    register_passkey(user)
    delete destroy_user_session_path

    sign_in_with_password(user)

    assert_redirected_to root_path
    follow_redirect!
    assert_equal user.id, session["warden.user.user.key"].first.first
  end

  test "a user with a second factor is not fully signed in until the second factor is verified" do
    user = create_confirmed_user(email: "pending-two-factor@example.com")
    sign_in user
    register_second_factor_credential(user)
    delete destroy_user_session_path

    sign_in_with_password(user)

    assert_redirected_to new_user_two_factor_authentication_path
    assert_nil session["warden.user.user.key"]
    assert_equal user.id, session[:current_authentication_resource_id]
  end

  test "a user with TOTP is not fully signed in until the TOTP code is verified" do
    user = create_confirmed_user(email: "pending-totp@example.com")
    user.create_totp_credential!(secret: TotpCredential.generate_secret)

    sign_in_with_password(user)

    assert_redirected_to new_user_two_factor_authentication_path
    assert_nil session["warden.user.user.key"]
    assert_equal user.id, session[:current_authentication_resource_id]
  end

  test "a user without MFA keeps the traditional password login" do
    user = create_confirmed_user(email: "plain-password@example.com")

    sign_in_with_password(user)

    assert_redirected_to root_path
    follow_redirect!
    assert_equal user.id, session["warden.user.user.key"].first.first
  end

  test "passkey login still works when TOTP is enabled" do
    user = create_confirmed_user(email: "passkey-with-totp@example.com")
    client = webauthn_client
    sign_in user
    register_passkey(user, client: client)
    user.create_totp_credential!(secret: TotpCredential.generate_secret)
    delete destroy_user_session_path

    login_with_passkey(user, client: client)

    assert_redirected_to root_path
    follow_redirect!
    assert_equal user.id, session["warden.user.user.key"].first.first
  end

  private

  def create_confirmed_user(email:)
    User.create!(
      name: "Login User",
      email: email,
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
  end
end
