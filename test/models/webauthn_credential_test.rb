# frozen_string_literal: true

require "test_helper"

class WebauthnCredentialTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      name: "Credential User",
      email: "credential-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
  end

  test "requires the cryptographic and display fields" do
    credential = @user.webauthn_credentials.new(authentication_factor: :first_factor)

    refute credential.valid?
    assert credential.errors[:external_id].present?
    assert credential.errors[:public_key].present?
    assert credential.errors[:name].present?
    assert credential.errors[:sign_count].present?
  end

  test "requires a globally unique external_id" do
    existing = create_credential
    duplicate = @user.webauthn_credentials.new(
      external_id: existing.external_id,
      name: "Duplicada",
      public_key: SecureRandom.base64(32),
      sign_count: 0,
      authentication_factor: :first_factor
    )

    refute duplicate.valid?
    assert duplicate.errors[:external_id].present?
  end

  test "exposes the authentication factor as an enum" do
    passkey = create_credential(factor: :first_factor)
    security_key = create_credential(factor: :second_factor)

    assert passkey.first_factor?
    refute passkey.second_factor?
    assert security_key.second_factor?
    refute security_key.first_factor?
  end

  test "the passkey scope only includes first factor credentials" do
    passkey = create_credential(factor: :first_factor)
    create_credential(factor: :second_factor)

    assert_equal [ passkey ], WebauthnCredential.passkey.to_a
  end

  test "belongs to the user and is removed with the user" do
    credential = create_credential

    assert_equal @user, credential.user
    assert_difference -> { WebauthnCredential.count }, -1 do
      @user.destroy!
    end
  end

  private

  def create_credential(factor: :first_factor)
    @user.webauthn_credentials.create!(
      external_id: SecureRandom.urlsafe_base64(16),
      name: "Credencial #{SecureRandom.hex(2)}",
      public_key: SecureRandom.base64(32),
      sign_count: 0,
      authentication_factor: factor
    )
  end
end
