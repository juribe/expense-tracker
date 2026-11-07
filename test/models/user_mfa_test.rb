# frozen_string_literal: true

require "test_helper"

class UserMfaTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      name: "MFA User",
      email: "mfa-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
  end

  test "enables the second factor when TOTP exists" do
    @user.create_totp_credential!(secret: TotpCredential.generate_secret)

    assert @user.reload.totp_enabled?
    assert @user.second_factor_enabled?
  end

  test "does not enable MFA with a passkey alone" do
    @user.passkeys.create!(
      external_id: SecureRandom.urlsafe_base64(16),
      name: "MacBook",
      public_key: SecureRandom.base64(32),
      sign_count: 0,
      authentication_factor: :first_factor
    )

    refute @user.reload.totp_enabled?
    refute @user.second_factor_enabled?
  end

  test "keeps WebAuthn second factor as an MFA method" do
    @user.second_factor_webauthn_credentials.create!(
      external_id: SecureRandom.urlsafe_base64(16),
      name: "Llave",
      public_key: SecureRandom.base64(32),
      sign_count: 0,
      authentication_factor: :second_factor
    )

    refute @user.reload.totp_enabled?
    assert @user.second_factor_enabled?
  end

  test "reports totp_enabled? consistently from the association" do
    refute @user.totp_enabled?

    @user.create_totp_credential!(secret: TotpCredential.generate_secret)

    assert @user.reload.totp_enabled?
    assert_equal @user.totp_credential, @user.totp_credential
  end
end
