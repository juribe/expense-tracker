# frozen_string_literal: true

require "test_helper"

# PremiumIdentities::Release: the only supported way to free a premium identity.
# It keeps the historical row and writes an audit log entry.
class PremiumIdentitiesReleaseTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      name: "Release Owner",
      email: "release-owner-#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    @admin = User.create!(
      name: "Release Admin",
      email: "release-admin-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      admin: true
    )
    @identity = PremiumIdentities::Protection.claim!(
      identity_type: "account_email",
      value: @user.email,
      user: @user
    )
  end

  test "marks the identity as released and records an audit log entry" do
    result = PremiumIdentities::Release.call(
      identity: @identity,
      actor: @admin,
      reason: "The original account was closed by mistake"
    )

    assert result.success?
    @identity.reload
    assert @identity.released?
    assert_equal @admin.id, @identity.released_by_user_id
    assert_equal "The original account was closed by mistake", @identity.release_reason

    audit = PaymentEngine::AuditLog.last
    assert_equal "premium_identity.released", audit.action
    assert_equal @admin.id.to_s, audit.actor_id
    assert_equal "PremiumIdentity", audit.auditable_type
    assert_equal @identity.id, audit.auditable_id
    assert_equal "The original account was closed by mistake", audit.reason
  end

  test "requires an audit reason" do
    result = PremiumIdentities::Release.call(identity: @identity, actor: @admin, reason: " ")

    assert_not result.success?
    assert_equal [ "El motivo de la liberación es obligatorio." ], result.errors
    assert_not @identity.reload.released?
  end

  test "does not release an identity twice" do
    PremiumIdentities::Release.call(identity: @identity, actor: @admin, reason: "first")

    result = PremiumIdentities::Release.call(identity: @identity, actor: @admin, reason: "second")

    assert_not result.success?
    assert_equal [ "La identidad ya fue liberada." ], result.errors
  end

  test "a released identity can be claimed by another account" do
    other = User.create!(
      name: "Release Reuse",
      email: "release-reuse-#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    PremiumIdentities::Release.call(identity: @identity, actor: @admin, reason: "support correction")

    reclaimed = PremiumIdentities::Protection.claim!(
      identity_type: "account_email",
      value: @user.email,
      user: other
    )

    assert_equal @identity.id, reclaimed.id
    assert_equal other.id, reclaimed.first_user_id
    assert_nil reclaimed.released_at
    assert_nil reclaimed.released_by_user_id
    assert_nil reclaimed.release_reason
  end

  test "once reclaimed, a released identity is closed for other accounts again" do
    other = User.create!(
      name: "Release Reuse First",
      email: "release-reuse-first-#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    third = User.create!(
      name: "Release Reuse Second",
      email: "release-reuse-second-#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    PremiumIdentities::Release.call(identity: @identity, actor: @admin, reason: "support correction")
    PremiumIdentities::Protection.claim!(
      identity_type: "account_email",
      value: @user.email,
      user: other
    )

    assert_raises(PremiumIdentities::Protection::Conflict) do
      PremiumIdentities::Protection.claim!(
        identity_type: "account_email",
        value: @user.email,
        user: third
      )
    end
  end
end
