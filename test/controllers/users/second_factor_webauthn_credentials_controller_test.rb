# frozen_string_literal: true

require "test_helper"

class Users::SecondFactorWebauthnCredentialsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = create_user(email: "second-factor-#{SecureRandom.hex(4)}@example.com")
    sign_in @user
  end

  test "a reauthenticated user registers a second factor credential and enables two factor" do
    assert_difference -> { @user.second_factor_webauthn_credentials.count }, 1 do
      register_second_factor_credential(@user, name: "Llave de seguridad")
    end

    assert @user.reload.second_factor_enabled?
    assert_redirected_to security_settings_path
    assert_equal I18n.t("devise.second_factor_webauthn_credentials.security_key_created",
                        default: "Verificación en dos pasos activada."),
                 flash[:notice]
  end

  test "adding another credential to an MFA account requires the current code" do
    @user.create_totp_credential!(secret: TotpCredential.generate_secret)
    post reauthenticate_security_settings_path, params: { current_password: "password123" }
    post user_security_key_registration_options_path
    options = JSON.parse(response.body)
    credential = webauthn_client.create(
      challenge: options.fetch("challenge"),
      rp_id: "localhost",
      user_verified: false
    )

    assert_no_difference -> { @user.second_factor_webauthn_credentials.count } do
      post user_second_factor_webauthn_credentials_path,
           params: { name: "Llave", public_key_credential: credential.to_json }
    end

    assert_redirected_to security_settings_path
    assert flash[:alert].present?
  end

  test "adding a credential to an MFA account succeeds with the current code" do
    totp = @user.create_totp_credential!(secret: TotpCredential.generate_secret)

    assert_difference -> { @user.second_factor_webauthn_credentials.count }, 1 do
      register_second_factor_credential(
        @user,
        name: "Llave",
        extra_params: { totp_code: ROTP::TOTP.new(totp.secret).now }
      )
    end
  end

  test "registration options require a recent reauthentication" do
    post user_security_key_registration_options_path

    assert_response :forbidden
  end

  test "creating a credential requires a recent reauthentication" do
    post reauthenticate_security_settings_path, params: { current_password: "password123" }
    post user_security_key_registration_options_path
    options = JSON.parse(response.body)
    credential = webauthn_client.create(challenge: options.fetch("challenge"), rp_id: "localhost",
                                        user_verified: false)

    travel 11.minutes do
      assert_no_difference -> { @user.second_factor_webauthn_credentials.count } do
        post user_second_factor_webauthn_credentials_path,
             params: { name: "Tarde", public_key_credential: credential.to_json }
      end
    end

    assert_redirected_to security_settings_path
    assert flash[:alert].present?
  end

  test "an invalid credential does not enable two factor" do
    post reauthenticate_security_settings_path, params: { current_password: "password123" }
    post user_security_key_registration_options_path
    invalid_credential = webauthn_client.create(
      challenge: WebAuthn.configuration.encoder.encode(SecureRandom.random_bytes(32)),
      rp_id: "localhost",
      user_verified: false
    )

    assert_no_difference -> { @user.second_factor_webauthn_credentials.count } do
      post user_second_factor_webauthn_credentials_path,
           params: { name: "Inválida", public_key_credential: invalid_credential.to_json }
    end

    refute @user.reload.second_factor_enabled?
    assert_redirected_to security_settings_path
  end

  test "the last second factor credential cannot be deleted" do
    credential = create_credential(@user)
    post reauthenticate_security_settings_path, params: { current_password: "password123" }

    assert_no_difference -> { @user.second_factor_webauthn_credentials.count } do
      delete user_second_factor_webauthn_credential_path(credential)
    end

    assert_redirected_to security_settings_path
    assert flash[:alert].present?
    assert @user.reload.second_factor_enabled?
  end

  test "a second factor credential can be deleted when another one remains" do
    credential = create_credential(@user)
    create_credential(@user, name: "Llave de respaldo")
    post reauthenticate_security_settings_path, params: { current_password: "password123" }

    assert_difference -> { @user.second_factor_webauthn_credentials.count }, -1 do
      delete user_second_factor_webauthn_credential_path(credential)
    end

    assert_redirected_to security_settings_path
    assert @user.reload.second_factor_enabled?
  end

  test "deleting a second factor credential requires a recent reauthentication" do
    credential = create_credential(@user)

    assert_no_difference -> { @user.second_factor_webauthn_credentials.count } do
      delete user_second_factor_webauthn_credential_path(credential)
    end

    assert_redirected_to security_settings_path
    assert flash[:alert].present?
  end

  test "a user cannot delete another user's second factor credential" do
    other_user = create_user(email: "other-second-factor@example.com")
    other_credential = create_credential(other_user)
    post reauthenticate_security_settings_path, params: { current_password: "password123" }

    assert_no_difference -> { other_user.second_factor_webauthn_credentials.count } do
      delete user_second_factor_webauthn_credential_path(other_credential)
    end

    assert_redirected_to security_settings_path
    assert flash[:alert].present?
  end

  test "promoting the last second factor credential to passkey is blocked" do
    credential = create_credential(@user)
    post reauthenticate_security_settings_path, params: { current_password: "password123" }

    patch user_second_factor_webauthn_credential_path(credential)

    assert_redirected_to security_settings_path
    assert_equal "second_factor", credential.reload.authentication_factor
    assert @user.reload.second_factor_enabled?
  end

  private

  def create_user(email:)
    User.create!(
      name: "Second Factor User",
      email: email,
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
  end

  def create_credential(user, name: "Llave de seguridad")
    user.webauthn_credentials.create!(
      external_id: SecureRandom.urlsafe_base64(16),
      name: name,
      public_key: SecureRandom.base64(32),
      sign_count: 0,
      authentication_factor: :second_factor
    )
  end
end
