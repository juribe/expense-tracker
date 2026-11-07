# frozen_string_literal: true

require "test_helper"

class Users::RecoveryCodeAuthenticationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Recovery User",
      email: "recovery-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
    create_second_factor_credential(@user)
    @codes = RecoveryCode.generate_for(@user)
  end

  test "a valid recovery code completes the second factor" do
    sign_in_with_password(@user)
    assert_redirected_to new_user_two_factor_authentication_path

    post user_recovery_code_authentication_path, params: { recovery_code: @codes.first }

    assert_redirected_to root_path
    follow_redirect!
    assert_equal @user.id, session["warden.user.user.key"].first.first
  end

  test "a recovery code can only be used once" do
    sign_in_with_password(@user)
    post user_recovery_code_authentication_path, params: { recovery_code: @codes.first }
    assert_redirected_to root_path
    delete destroy_user_session_path

    sign_in_with_password(@user)
    post user_recovery_code_authentication_path, params: { recovery_code: @codes.first }

    assert_redirected_to new_user_two_factor_authentication_path
    assert_nil session["warden.user.user.key"]
  end

  test "an invalid recovery code does not complete the second factor" do
    sign_in_with_password(@user)

    post user_recovery_code_authentication_path,
         params: { recovery_code: "AAAA-BBBB-CCCC-DDDD-EEEE" }

    assert_redirected_to new_user_two_factor_authentication_path
    assert_nil session["warden.user.user.key"]
  end

  test "a recovery code from another user is rejected" do
    other_user = User.create!(
      name: "Other Recovery User",
      email: "other-recovery-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
    other_code = RecoveryCode.generate_for(other_user).first
    sign_in_with_password(@user)

    post user_recovery_code_authentication_path, params: { recovery_code: other_code }

    assert_redirected_to new_user_two_factor_authentication_path
    assert_nil session["warden.user.user.key"]
  end

  test "a recovery code cannot be used without a pending password sign in" do
    delete destroy_user_session_path

    post user_recovery_code_authentication_path, params: { recovery_code: @codes.first }

    assert_redirected_to new_user_session_path
    assert_nil session["warden.user.user.key"]
  end

  test "a recovery code completes the second factor when TOTP is the only MFA method" do
    user = User.create!(
      name: "TOTP Recovery User",
      email: "totp-recovery-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
    user.create_totp_credential!(secret: TotpCredential.generate_secret)
    codes = RecoveryCode.generate_for(user)

    sign_in_with_password(user)
    assert_redirected_to new_user_two_factor_authentication_path

    post user_recovery_code_authentication_path, params: { recovery_code: codes.first }

    assert_redirected_to root_path
    follow_redirect!
    assert_equal user.id, session["warden.user.user.key"].first.first
  end

  private

  def create_second_factor_credential(user)
    user.webauthn_credentials.create!(
      external_id: SecureRandom.urlsafe_base64(16),
      name: "Llave de seguridad",
      public_key: SecureRandom.base64(32),
      sign_count: 0,
      authentication_factor: :second_factor
    )
  end
end
