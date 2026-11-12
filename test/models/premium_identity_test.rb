# frozen_string_literal: true

require "test_helper"

# PremiumIdentity: the permanent, historical fingerprint of an identifier used
# to access premium features. It is independent from the active configuration
# and from the user row, so deleting any of them does not release the identity.
class PremiumIdentityTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      name: "Premium Identity",
      email: "premium-identity-#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
  end

  test "accepts only the supported identity types" do
    identity = PremiumIdentity.new(
      identity_type: "unknown",
      fingerprint: PremiumIdentities::Fingerprint.call(identity_type: "account_email", value: "a@example.com"),
      first_used_at: Time.current
    )

    assert_not identity.valid?
    assert_includes identity.errors[:identity_type], "no está incluido en la lista"
  end

  test "builds a deterministic HMAC fingerprint for the normalized identifier" do
    first = PremiumIdentities::Fingerprint.call(identity_type: "account_email", value: "  User@Example.com ")
    second = PremiumIdentities::Fingerprint.call(identity_type: "account_email", value: "user@example.com")

    assert_equal first, second
    assert_match(/\A[0-9a-f]{64}\z/, first)
  end

  test "does not use a plain SHA256 digest of the identifier" do
    fingerprint = PremiumIdentities::Fingerprint.call(identity_type: "account_email", value: "user@example.com")

    refute_equal Digest::SHA256.hexdigest("user@example.com"), fingerprint
  end

  test "includes the identity type in the fingerprint" do
    account = PremiumIdentities::Fingerprint.call(identity_type: "account_email", value: "user@example.com")
    gmail = PremiumIdentities::Fingerprint.call(identity_type: "gmail", value: "user@example.com")

    assert_not_equal account, gmail
  end

  test "normalizes Gmail aliases to the same mailbox" do
    first = PremiumIdentities::Fingerprint.call(identity_type: "gmail", value: "User.Name+receipts@googlemail.com")
    second = PremiumIdentities::Fingerprint.call(identity_type: "gmail", value: "username@gmail.com")

    assert_equal first, second
  end

  test "normalizes WhatsApp numbers to E.164 before fingerprinting" do
    first = PremiumIdentities::Fingerprint.call(identity_type: "whatsapp", value: "+57 300 123 4567")
    second = PremiumIdentities::Fingerprint.call(identity_type: "whatsapp", value: "0057-300-123-4567")

    assert_equal first, second
  end

  test "returns nil for a blank identifier" do
    assert_nil PremiumIdentities::Fingerprint.call(identity_type: "account_email", value: "   ")
  end

  test "the fingerprint is unique at the model and database level" do
    fingerprint = PremiumIdentities::Fingerprint.call(identity_type: "account_email", value: @user.email)
    PremiumIdentity.create!(
      identity_type: "account_email",
      fingerprint: fingerprint,
      first_user: @user,
      first_used_at: Time.current
    )

    duplicate = PremiumIdentity.new(
      identity_type: "account_email",
      fingerprint: fingerprint,
      first_user: @user,
      first_used_at: Time.current
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:fingerprint], "ya está en uso"
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test "released identities can be used by another account" do
    other = User.create!(
      name: "Other Premium Identity",
      email: "other-premium-#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    identity = PremiumIdentity.create!(
      identity_type: "account_email",
      fingerprint: PremiumIdentities::Fingerprint.call(identity_type: "account_email", value: "shared@example.com"),
      first_user: @user,
      first_used_at: Time.current
    )

    refute identity.available_to?(other)

    identity.update!(released_at: Time.current, released_by_user: other, release_reason: "admin correction")

    assert identity.released?
    assert identity.available_to?(other)
  end

  test "survives user deletion and keeps blocking the identity" do
    identity = PremiumIdentity.create!(
      identity_type: "account_email",
      fingerprint: PremiumIdentities::Fingerprint.call(identity_type: "account_email", value: @user.email),
      first_user: @user,
      first_used_at: Time.current
    )

    @user.destroy!

    identity.reload
    assert_nil identity.first_user_id
    assert_not identity.released?
    assert identity.persisted?
  end
end
