# frozen_string_literal: true

require "test_helper"

# PaymentEngine::UserAccess + PremiumIdentities::MembershipHistory.
# An account whose email identity already paid/used premium keeps the free
# plan and the renewal options, but cannot obtain premium again.
class PaymentEngineUserAccessPremiumIdentityTest < ActiveSupport::TestCase
  setup do
    @membership_type = PaymentEngine::MembershipType.create!(
      name: "Access Identity Test",
      code: "ACCESS_ID_#{SecureRandom.hex(6)}",
      status: "active"
    )
    @user = User.create!(
      name: "Access Identity User",
      email: "access_identity_#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
  end

  test "a returning identity account keeps free access without premium" do
    create_used_identity

    with_paid_access_required(true) do
      assert_equal false, access.need_membership?
      assert_equal true, access.free_membership_used?
      assert_equal true, access.free_plan_available?
      assert_equal false, access.access_premium?
      assert_equal true, access.renewal_prompt?
    end
  end

  test "a returning identity account cannot start a new trial" do
    create_used_identity

    with_paid_access_required(true) do
      assert_equal false, PaymentEngine::AccessPolicy.can_start_trial?(@user)
    end
  end

  test "a returning identity account still sees the identity membership as historical" do
    identity = create_used_identity

    assert_equal identity.payment_engine_membership_id,
                 PremiumIdentities::MembershipHistory.membership_for(@user).id
    assert_equal identity.payment_engine_membership_id, access.current_membership.id
  end

  test "a returning identity account sees the renewal prompt on the dashboard" do
    create_used_identity

    with_paid_access_required(true) do
      assert_equal true, access.renewal_prompt?
    end
  end

  test "an administrative release restores the normal access questions" do
    identity = create_used_identity
    admin = User.create!(
      name: "Access Release Admin",
      email: "access_release_admin_#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    PremiumIdentities::Release.call(identity: identity, actor: admin, reason: "Support correction")

    with_paid_access_required(true) do
      assert_equal true, access.need_membership?
      assert_equal false, access.free_membership_used?
      assert_equal true, PaymentEngine::AccessPolicy.can_start_trial?(@user)
    end
  end

  test "free access questions stay cached and invalidate when the identity changes" do
    create_used_identity
    user_access = PaymentEngine::UserAccess.new(@user.id)
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    with_paid_access_required(true) do
      assert_equal false, user_access.need_membership?
      assert_equal true, user_access.free_membership_used?
    end

    PremiumIdentities::Release.call(
      identity: PremiumIdentities::MembershipHistory.identity_for(@user),
      reason: "Support correction"
    )

    with_paid_access_required(true) do
      assert_equal true, user_access.need_membership?
      assert_equal false, user_access.free_membership_used?
    end
  ensure
    Rails.cache = original_cache
  end

  private

  def access
    PaymentEngine::UserAccess.new(@user.id)
  end

  # Simulates the reported case: the account email already had a premium
  # membership owned by another (or deleted) account, so the new account is a
  # returning identity.
  def create_used_identity
    owner = User.create!(
      name: "Access Identity Owner",
      email: "access_identity_owner_#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    membership = PaymentEngine::Membership.create!(
      owner: owner,
      membership_type: @membership_type,
      status: "active",
      source: "trial",
      starts_at: 1.month.ago,
      expires_at: 1.day.ago
    )
    PremiumIdentities::Protection.claim!(
      identity_type: "account_email",
      value: @user.email,
      user: owner,
      membership: membership
    )
  end

  def with_paid_access_required(required)
    stub_method(PaymentEngine::Configuration, :paid_access_required?, required) do
      yield
    end
  end
end
