# frozen_string_literal: true

# Helpers for exercising WebAuthn ceremonies with a simulated authenticator.
# No biometric sensor or real browser is required.
module WebauthnTestHelper
  TEST_ORIGIN = "http://localhost:3000"
  TEST_RP_ID = "localhost"

  def webauthn_client(origin: TEST_ORIGIN)
    require "webauthn/fake_client"
    @webauthn_clients ||= {}
    @webauthn_clients[origin] ||= WebAuthn::FakeClient.new(origin)
  end

  def new_webauthn_client(origin: TEST_ORIGIN)
    require "webauthn/fake_client"
    WebAuthn::FakeClient.new(origin)
  end

  def register_passkey(user, name: "Mi MacBook", client: webauthn_client)
    post reauthenticate_security_settings_path, params: { current_password: "password123" }
    post user_passkey_registration_options_path
    assert_response :success

    options = JSON.parse(response.body)
    credential = client.create(
      challenge: options.fetch("challenge"),
      rp_id: TEST_RP_ID,
      user_verified: true
    )

    post user_passkeys_path, params: { name: name, public_key_credential: credential.to_json }
    credential
  end

  def login_with_passkey(user, client: webauthn_client)
    post user_passkey_authentication_options_path
    assert_response :success

    options = JSON.parse(response.body)
    credential = client.get(
      challenge: options.fetch("challenge"),
      rp_id: TEST_RP_ID,
      user_verified: true,
      user_handle: webauthn_user_handle(user)
    )

    post user_session_path, params: { public_key_credential: credential.to_json }
    credential
  end

  # FakeClient expects the raw user handle and encodes it in the assertion.
  # webauthn_id is already encoded, so decode it first to avoid double encoding.
  def webauthn_user_handle(user)
    WebAuthn.configuration.encoder.decode(user.reload.webauthn_id)
  end

  def register_second_factor_credential(user, name: "Llave de seguridad", client: webauthn_client)
    post reauthenticate_security_settings_path, params: { current_password: "password123" }
    post user_security_key_registration_options_path
    assert_response :success

    options = JSON.parse(response.body)
    credential = client.create(
      challenge: options.fetch("challenge"),
      rp_id: TEST_RP_ID,
      user_verified: false
    )

    post user_second_factor_webauthn_credentials_path,
         params: { name: name, public_key_credential: credential.to_json }
    credential
  end

  def complete_second_factor(client: webauthn_client)
    post user_security_key_authentication_options_path
    assert_response :success

    options = JSON.parse(response.body)
    credential = client.get(
      challenge: options.fetch("challenge"),
      rp_id: TEST_RP_ID,
      user_verified: false
    )

    post user_two_factor_authentication_path,
         params: { public_key_credential: credential.to_json }
    credential
  end

  def sign_in_with_password(user, password: "password123")
    post user_session_path, params: { user: { email: user.email, password: password } }
  end
end
