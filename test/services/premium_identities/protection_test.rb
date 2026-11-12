# frozen_string_literal: true

require "test_helper"

# PremiumIdentities::Protection: central claim/check service for the identities
# that grant access to premium features. A row is created on first use and can
# only be used by the same account until an administrator releases it.
class PremiumIdentitiesProtectionTest < ActiveSupport::TestCase
  setup do
    @user = create_user("protection-owner")
    @other_user = create_user("protection-other")
    @membership_type = PaymentEngine::MembershipType.create!(
      name: "Protection Test",
      code: "PROTECTION_#{SecureRandom.hex(6)}",
      status: "active"
    )
    @membership = create_membership(@user)
  end

  test "claims an identity for the first user with its membership and first use date" do
    identity = PremiumIdentities::Protection.claim!(
      identity_type: "account_email",
      value: @user.email,
      user: @user,
      membership: @membership
    )

    assert_equal "account_email", identity.identity_type
    assert_equal @user.id, identity.first_user_id
    assert_equal @membership.id, identity.payment_engine_membership_id
    assert identity.first_used_at.present?
  end

  test "re-claiming the same identity for the same user is idempotent" do
    first = PremiumIdentities::Protection.claim!(
      identity_type: "gmail",
      value: "same@gmail.com",
      user: @user
    )

    second = PremiumIdentities::Protection.claim!(
      identity_type: "gmail",
      value: "SAME@gmail.com",
      user: @user,
      membership: @membership
    )

    assert_equal first.id, second.id
    assert_equal 1, PremiumIdentity.count
    assert_equal @membership.id, second.payment_engine_membership_id
  end

  test "another account cannot claim an identity already used by a different user" do
    PremiumIdentities::Protection.claim!(
      identity_type: "whatsapp",
      value: "+57 300 123 4567",
      user: @user
    )

    error = assert_raises(PremiumIdentities::Protection::Conflict) do
      PremiumIdentities::Protection.claim!(
        identity_type: "whatsapp",
        value: "573001234567",
        user: @other_user
      )
    end

    assert_equal "Esta identidad ya está asociada a otra cuenta.", error.message
    assert_equal @user.id, PremiumIdentity.find_by(identity_type: "whatsapp").first_user_id
  end

  test "does not release an identity when the membership expires" do
    PremiumIdentities::Protection.claim!(
      identity_type: "account_email",
      value: @user.email,
      user: @user,
      membership: @membership
    )
    @membership.update!(status: "expired", expires_at: 1.day.ago)

    assert_not PremiumIdentities::Protection.available?(
      identity_type: "account_email",
      value: @user.email,
      user: @other_user
    )
  end

  test "does not release an identity when the first user is deleted" do
    email = @user.email
    PremiumIdentities::Protection.claim!(
      identity_type: "account_email",
      value: email,
      user: @user,
      membership: @membership
    )
    @user.destroy!

    assert_not PremiumIdentities::Protection.available?(
      identity_type: "account_email",
      value: email,
      user: @other_user
    )
    assert_not PremiumIdentity.find_by(identity_type: "account_email").released?
  end

  test "available? is true for a new identity, the same user and a released identity" do
    assert PremiumIdentities::Protection.available?(
      identity_type: "redirect_email",
      value: "new@example.com",
      user: @user
    )

    identity = PremiumIdentities::Protection.claim!(
      identity_type: "redirect_email",
      value: "new@example.com",
      user: @user
    )

    assert PremiumIdentities::Protection.available?(
      identity_type: "redirect_email",
      value: "new@example.com",
      user: @user
    )
    assert_not PremiumIdentities::Protection.available?(
      identity_type: "redirect_email",
      value: "new@example.com",
      user: @other_user
    )

    identity.update!(released_at: Time.current, release_reason: "manual release")

    assert PremiumIdentities::Protection.available?(
      identity_type: "redirect_email",
      value: "new@example.com",
      user: @other_user
    )
  end

  test "a losing concurrent claim does not take ownership from the winner" do
    winner = PremiumIdentity.create!(
      identity_type: "gmail",
      fingerprint: PremiumIdentities::Fingerprint.call(identity_type: "gmail", value: "race@gmail.com"),
      first_user: @other_user,
      first_used_at: Time.current
    )
    original_find = PremiumIdentity.method(:find_by)
    calls = 0

    stub_method(PremiumIdentity, :find_by, lambda { |*args, **kwargs|
      calls += 1
      calls == 1 ? nil : original_find.call(*args, **kwargs)
    }) do
      stub_method(PremiumIdentity, :create!, ->(_attributes) { raise ActiveRecord::RecordNotUnique }) do
        assert_raises(PremiumIdentities::Protection::Conflict) do
          PremiumIdentities::Protection.claim!(
            identity_type: "gmail",
            value: "race@gmail.com",
            user: @user
          )
        end
      end
    end

    assert_equal @other_user.id, winner.first_user_id
    assert_equal 1, PremiumIdentity.where(identity_type: "gmail").count
  end

  private

  def create_user(prefix)
    User.create!(
      name: prefix.titleize,
      email: "#{prefix}-#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
  end

  def create_membership(user)
    PaymentEngine::Membership.create!(
      owner: user,
      membership_type: @membership_type,
      status: "active",
      source: "purchase",
      starts_at: 1.day.ago,
      expires_at: 1.month.from_now
    )
  end
end
