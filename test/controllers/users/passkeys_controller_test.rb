# frozen_string_literal: true

require "test_helper"

class Users::PasskeysControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = create_user(email: "passkeys-#{SecureRandom.hex(4)}@example.com")
    sign_in @user
  end

  test "unauthenticated visitors cannot request passkey registration options" do
    delete destroy_user_session_path

    post user_passkey_registration_options_path

    assert_redirected_to new_user_session_path
  end

  test "registration options require a recent reauthentication" do
    post user_passkey_registration_options_path

    assert_response :forbidden
    assert_equal 0, @user.reload.passkeys.count
  end

  test "a reauthenticated user registers a valid passkey" do
    assert_difference -> { @user.passkeys.count }, 1 do
      register_passkey(@user, name: "MacBook personal")
    end

    credential = @user.passkeys.order(:created_at).last
    assert_equal "MacBook personal", credential.name
    assert_equal "first_factor", credential.authentication_factor
    assert_redirected_to security_settings_path
    assert_equal I18n.t("devise.passkeys.passkey_created",
                        default: "Passkey agregada correctamente."),
                 flash[:notice]
  end

  test "adding a passkey to an MFA account requires the current code" do
    @user.create_totp_credential!(secret: TotpCredential.generate_secret)
    post reauthenticate_security_settings_path, params: { current_password: "password123" }
    post user_passkey_registration_options_path
    options = JSON.parse(response.body)
    credential = webauthn_client.create(
      challenge: options.fetch("challenge"),
      rp_id: "localhost",
      user_verified: true
    )

    assert_no_difference -> { @user.passkeys.count } do
      post user_passkeys_path, params: { name: "MacBook", public_key_credential: credential.to_json }
    end

    assert_redirected_to security_settings_path
    assert flash[:alert].present?
  end

  test "adding a passkey to an MFA account succeeds with the current code" do
    totp = @user.create_totp_credential!(secret: TotpCredential.generate_secret)

    assert_difference -> { @user.passkeys.count }, 1 do
      register_passkey(
        @user,
        name: "MacBook",
        extra_params: { totp_code: ROTP::TOTP.new(totp.secret).now }
      )
    end
  end

  test "registering a passkey does not enable two factor authentication" do
    register_passkey(@user, name: "MacBook personal")

    refute @user.reload.second_factor_enabled?
  end

  test "an invalid WebAuthn response does not create a credential" do
    post reauthenticate_security_settings_path, params: { current_password: "password123" }
    post user_passkey_registration_options_path
    invalid_credential = webauthn_client.create(
      challenge: WebAuthn.configuration.encoder.encode(SecureRandom.random_bytes(32)),
      rp_id: "localhost",
      user_verified: true
    )

    assert_no_difference -> { @user.passkeys.count } do
      post user_passkeys_path,
           params: { name: "Credencial falsa", public_key_credential: invalid_credential.to_json }
    end

    assert_redirected_to security_settings_path
    assert_equal I18n.t("devise.failure.passkey_verification_failed",
                        default: "No pudimos verificar tu identidad. Inténtalo nuevamente."),
                 flash[:alert]
  end

  test "a registration challenge cannot be reused" do
    credential = register_passkey(@user, name: "MacBook personal")

    assert_no_difference -> { @user.passkeys.count } do
      post user_passkeys_path,
           params: { name: "Segunda vez", public_key_credential: credential.to_json }
    end

    assert_redirected_to security_settings_path
    assert flash[:alert].present?
  end

  test "an expired registration challenge is rejected" do
    post reauthenticate_security_settings_path, params: { current_password: "password123" }
    post user_passkey_registration_options_path
    options = JSON.parse(response.body)
    credential = webauthn_client.create(
      challenge: options.fetch("challenge"),
      rp_id: "localhost",
      user_verified: true
    )

    travel 6.minutes do
      assert_no_difference -> { @user.passkeys.count } do
        post user_passkeys_path,
             params: { name: "Tarde", public_key_credential: credential.to_json }
      end
    end

    assert_redirected_to security_settings_path
    assert flash[:alert].present?
  end

  test "a user deletes their own passkey" do
    credential = create_credential(@user, name: "MacBook personal")
    post reauthenticate_security_settings_path, params: { current_password: "password123" }

    assert_difference -> { @user.passkeys.count }, -1 do
      delete user_passkey_path(credential)
    end

    assert_redirected_to security_settings_path
    assert_equal I18n.t("devise.passkeys.passkey_deleted",
                        default: "Passkey eliminada correctamente."),
                 flash[:notice]
  end

  test "a user cannot delete another user's passkey" do
    other_user = create_user(email: "other-passkey@example.com")
    other_credential = create_credential(other_user, name: "Dispositivo ajeno")
    post reauthenticate_security_settings_path, params: { current_password: "password123" }

    assert_no_difference -> { other_user.passkeys.count } do
      delete user_passkey_path(other_credential)
    end

    assert_redirected_to security_settings_path
    assert flash[:alert].present?
  end

  test "deleting a passkey requires a recent reauthentication" do
    credential = create_credential(@user, name: "MacBook personal")

    assert_no_difference -> { @user.passkeys.count } do
      delete user_passkey_path(credential)
    end

    assert_redirected_to security_settings_path
    assert flash[:alert].present?
  end

  private

  def create_user(email:)
    User.create!(
      name: "Passkey User",
      email: email,
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
  end

  def create_credential(user, name:)
    user.webauthn_credentials.create!(
      external_id: SecureRandom.urlsafe_base64(16),
      name: name,
      public_key: SecureRandom.base64(32),
      sign_count: 0,
      authentication_factor: :first_factor
    )
  end
end
