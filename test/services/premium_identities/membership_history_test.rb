# frozen_string_literal: true

require "test_helper"

# PremiumIdentities::MembershipHistory exposes the membership behind an account
# email identity. A new account with a used identity keeps free access but
# cannot obtain premium again.
class PremiumIdentitiesMembershipHistoryTest < ActiveSupport::TestCase
  setup do
    @membership_type = PaymentEngine::MembershipType.create!(
      name: "Membership History Test",
      code: "MEMHIST_#{SecureRandom.hex(6)}",
      status: "active"
    )
  end

  test "used_by? is false for a fresh account without identity" do
    user = create_user("fresh-history")

    assert_equal false, PremiumIdentities::MembershipHistory.used_by?(user)
  end

  test "used_by? is true when the identity belongs to a deleted account" do
    original = create_user("history-deleted")
    membership = create_membership(original)
    PremiumIdentities::Protection.claim!(
      identity_type: "account_email",
      value: original.email,
      user: original,
      membership: membership
    )
    email = original.email
    original.destroy!

    replacement = create_user("history-replacement", email: email)

    assert_equal true, PremiumIdentities::MembershipHistory.used_by?(replacement)
    assert_equal membership.id, PremiumIdentities::MembershipHistory.membership_for(replacement).id
  end

  test "used_by? is true when the identity belongs to another account" do
    owner = create_user("history-owner")
    create_membership(owner)
    PremiumIdentities::Protection.claim!(
      identity_type: "account_email",
      value: "shared-history@gmail.com",
      user: owner,
      membership: PaymentEngine::Membership.where(owner: owner).first
    )
    other = create_user("history-other", email: "shared-history@gmail.com")

    assert_equal true, PremiumIdentities::MembershipHistory.used_by?(other)
  end

  test "used_by? is false for the identity owner" do
    owner = create_user("history-self")
    membership = create_membership(owner)
    PremiumIdentities::Protection.claim!(
      identity_type: "account_email",
      value: owner.email,
      user: owner,
      membership: membership
    )

    assert_equal false, PremiumIdentities::MembershipHistory.used_by?(owner)
  end

  test "used_by? is false after an administrative release" do
    original = create_user("history-released")
    membership = create_membership(original)
    identity = PremiumIdentities::Protection.claim!(
      identity_type: "account_email",
      value: original.email,
      user: original,
      membership: membership
    )
    admin = create_user("history-admin")
    PremiumIdentities::Release.call(identity: identity, actor: admin, reason: "Support correction")

    assert_equal false, PremiumIdentities::MembershipHistory.used_by?(original)
  end

  private

  def create_user(prefix, email: nil)
    User.create!(
      name: prefix.titleize,
      email: email || "#{prefix}-#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
  end

  def create_membership(user)
    PaymentEngine::Membership.create!(
      owner: user,
      membership_type: @membership_type,
      status: "active",
      source: "trial",
      starts_at: 1.day.ago,
      expires_at: 1.day.from_now
    )
  end
end
