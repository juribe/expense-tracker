# frozen_string_literal: true

require "test_helper"

class UserWebauthnTest < ActiveSupport::TestCase
  setup do
    @user = create_user
  end

  test "generates and persists a stable webauthn_id on demand" do
    assert_nil @user.webauthn_id

    first_id = @user.ensure_webauthn_id!

    assert first_id.present?
    assert_equal first_id, @user.reload.webauthn_id
    assert_equal first_id, @user.ensure_webauthn_id!
  end

  test "webauthn_id is unique when present" do
    other_user = create_user
    @user.update_column(:webauthn_id, "shared-webauthn-id")

    other_user.webauthn_id = "shared-webauthn-id"

    refute other_user.valid?
    assert other_user.errors[:webauthn_id].present?
  end

  test "separates passkeys from second factor credentials" do
    passkey = create_credential(@user, factor: :first_factor, name: "MacBook")
    security_key = create_credential(@user, factor: :second_factor, name: "Llave")

    assert_equal [ passkey ], @user.passkeys.to_a
    assert_equal [ security_key ], @user.second_factor_webauthn_credentials.to_a
    assert_equal 2, @user.webauthn_credentials.count
  end

  test "registering a passkey does not enable two factor authentication" do
    create_credential(@user, factor: :first_factor, name: "MacBook")

    refute @user.reload.second_factor_enabled?
  end

  test "a second factor credential enables two factor authentication" do
    create_credential(@user, factor: :second_factor, name: "Llave")

    assert @user.reload.second_factor_enabled?
  end

  test "a user without credentials does not have two factor enabled" do
    refute @user.second_factor_enabled?
  end

  test "destroying a user removes webauthn credentials and recovery codes" do
    create_credential(@user, factor: :first_factor, name: "MacBook")
    create_credential(@user, factor: :second_factor, name: "Llave")
    RecoveryCode.generate_for(@user)

    assert_difference -> { WebauthnCredential.count }, -2 do
      assert_difference -> { RecoveryCode.count }, -10 do
        @user.destroy!
      end
    end
  end

  private

  def create_user
    User.create!(
      name: "WebAuthn User",
      email: "webauthn-user-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
  end

  def create_credential(user, factor:, name:)
    user.webauthn_credentials.create!(
      external_id: SecureRandom.urlsafe_base64(16),
      name: name,
      public_key: SecureRandom.base64(32),
      sign_count: 0,
      authentication_factor: factor
    )
  end
end
