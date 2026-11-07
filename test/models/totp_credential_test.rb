# frozen_string_literal: true

require "test_helper"

class TotpCredentialTest < ActiveSupport::TestCase
  setup do
    @user = create_user(email: "totp-model-#{SecureRandom.hex(4)}@example.com")
  end

  test "encrypts the TOTP secret at rest" do
    secret = TotpCredential.generate_secret
    credential = create_credential(@user, secret: secret)

    assert_equal secret, credential.reload.secret

    raw_secret = TotpCredential.connection.select_value(
      TotpCredential.sanitize_sql([
        "SELECT secret FROM totp_credentials WHERE id = ?",
        credential.id
      ])
    )

    assert raw_secret.present?
    refute_equal secret, raw_secret
  end

  test "generates a unique base32 secret for every credential" do
    first = TotpCredential.generate_secret
    second = TotpCredential.generate_secret

    assert_match(/\A[A-Z2-7]+\z/, first)
    assert_equal 32, first.length
    refute_equal first, second
  end

  test "builds an otpauth URI compatible with authenticator apps" do
    credential = create_credential(@user)

    uri = credential.provisioning_uri

    assert_includes uri, "otpauth://totp/"
    assert_includes uri, "issuer=Yogasto"
    assert_includes uri, ERB::Util.url_encode(@user.email)
    assert_includes uri, credential.secret
  end

  test "accepts a current code" do
    credential = create_credential(@user)
    code = ROTP::TOTP.new(credential.secret).now

    assert credential.verify_and_consume!(code)
  end

  test "rejects an incorrect code" do
    credential = create_credential(@user)
    wrong_code = ROTP::TOTP.new(TotpCredential.generate_secret).now

    refute credential.verify_and_consume!(wrong_code)
  end

  test "rejects a code outside the tolerance window" do
    travel_to(Time.zone.parse("2026-01-01 12:00:00")) do
      credential = create_credential(@user)
      expired_code = ROTP::TOTP.new(credential.secret).at(Time.current - 5.minutes)

      refute credential.verify_and_consume!(expired_code)
    end
  end

  test "accepts a code within the clock drift window" do
    travel_to(Time.zone.parse("2026-01-01 12:00:00")) do
      credential = create_credential(@user)
      previous_step_code = ROTP::TOTP.new(credential.secret).at(Time.current - 30.seconds)

      assert credential.verify_and_consume!(previous_step_code)
    end
  end

  test "prevents reusing the same code" do
    travel_to(Time.zone.parse("2026-01-01 12:00:00")) do
      credential = create_credential(@user)
      code = ROTP::TOTP.new(credential.secret).now

      assert credential.verify_and_consume!(code)
      refute credential.verify_and_consume!(code)
    end
  end

  test "allows only one credential per user" do
    create_credential(@user)
    duplicate = TotpCredential.new(user: @user, secret: TotpCredential.generate_secret)

    refute duplicate.valid?
    assert duplicate.errors[:user_id].present?
  end

  test "removes the credential when the user is destroyed" do
    create_credential(@user)

    assert_difference -> { TotpCredential.count }, -1 do
      @user.destroy!
    end
  end

  test "does not reuse secrets between users" do
    other_user = create_user(email: "other-totp-model-#{SecureRandom.hex(4)}@example.com")
    first = create_credential(@user)
    second = create_credential(other_user)

    refute_equal first.secret, second.secret
  end

  private

  def create_user(email:)
    User.create!(
      name: "TOTP User",
      email: email,
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
  end

  def create_credential(user, secret: TotpCredential.generate_secret)
    user.create_totp_credential!(secret: secret)
  end
end
