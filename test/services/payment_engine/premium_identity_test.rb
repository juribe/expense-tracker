# frozen_string_literal: true

require "test_helper"

# Premium identities are recorded when a membership is granted and when the
# premium channels (WhatsApp, Gmail, redirect email) are associated. The
# historical record blocks reuse even after the user, membership or
# configuration disappears.
class PaymentEnginePremiumIdentityTest < ActiveSupport::TestCase
  setup do
    @membership_type = PaymentEngine::MembershipType.find_or_create_by!(code: "BASIC") do |type|
      type.name = "Membresía Básica"
      type.status = "active"
    end
    PaymentEngine::Setting.current.update!(free_trial_enabled: true, free_trial_once_per_user: true)
  end

  test "starting a trial records the account email identity with the trial membership" do
    user = create_user("trial-identity")

    result = PaymentEngine::Memberships::StartFreeTrial.call(owner: user)

    assert result.success?
    identity = account_email_identity(user.email)
    assert identity
    assert_equal user.id, identity.first_user_id
    assert_equal result.record.id, identity.payment_engine_membership_id
    assert_equal "account_email", identity.identity_type
  end

  test "a new account cannot start a trial with an email from a deleted premium account" do
    user = create_user("deleted-trial")
    PaymentEngine::Memberships::StartFreeTrial.call(owner: user)
    email = user.email
    user.destroy!

    new_user = create_user("deleted-trial-replacement", email: email)
    result = PaymentEngine::Memberships::StartFreeTrial.call(owner: new_user)

    assert_not result.success?
    assert_includes result.errors, "Esta identidad ya está asociada a otra cuenta."
    assert_equal 0, PaymentEngine::Membership.where(owner: new_user).count
    assert PremiumIdentity.find_by(identity_type: "account_email", first_user_id: nil)
  end

  test "an expired membership does not free the account email identity" do
    user = create_user("expired-trial")
    result = PaymentEngine::Memberships::StartFreeTrial.call(owner: user)
    result.record.update!(status: "expired", expires_at: 1.day.ago)
    original_email = user.email
    user.update_column(:email, "moved-#{SecureRandom.hex(4)}@example.com")

    new_user = create_user("expired-trial-replacement", email: original_email)
    trial = PaymentEngine::Memberships::StartFreeTrial.call(owner: new_user)

    assert_not trial.success?
    assert_equal 0, PaymentEngine::Membership.where(owner: new_user).count
  end

  test "can_start_trial? is false for an email already used by another account" do
    owner = create_user("access-policy-owner")
    PremiumIdentities::Protection.claim!(
      identity_type: "account_email",
      value: "used-email@example.com",
      user: owner
    )
    new_user = create_user("access-policy-new", email: "used-email@example.com")

    assert_not PaymentEngine::AccessPolicy.can_start_trial?(new_user)
  end

  test "can_start_trial? remains true for a fresh free account" do
    user = create_user("fresh-trial")

    assert PaymentEngine::AccessPolicy.can_start_trial?(user)
  end

  test "granting a paid membership records the account email identity" do
    user = create_user("paid-grant")

    result = PaymentEngine::Memberships::Grant.call(
      owner: user,
      membership_type: @membership_type,
      source: "purchase"
    )

    assert result.success?
    identity = account_email_identity(user.email)
    assert identity
    assert_equal result.record.id, identity.payment_engine_membership_id
  end

  test "a paid membership cannot reuse an email bound to another account" do
    original = create_user("paid-original")
    PaymentEngine::Memberships::Grant.call(
      owner: original,
      membership_type: @membership_type,
      source: "purchase"
    )
    original.destroy!

    replacement = create_user("paid-replacement", email: original.email)
    result = PaymentEngine::Memberships::Grant.call(
      owner: replacement,
      membership_type: @membership_type,
      source: "purchase"
    )

    assert_not result.success?
    assert_includes result.errors, "Esta identidad ya está asociada a otra cuenta."
    assert_equal 0, PaymentEngine::Membership.where(owner: replacement).count
  end

  private

  def create_user(prefix, email: nil)
    User.create!(
      name: prefix.titleize,
      email: email || "#{prefix}-#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
  end

  def account_email_identity(email)
    PremiumIdentity.find_by(
      identity_type: "account_email",
      fingerprint: PremiumIdentities::Fingerprint.call(identity_type: "account_email", value: email)
    )
  end
end
