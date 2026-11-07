# frozen_string_literal: true

require "test_helper"

class PaymentEngineUserAccessTest < ActiveSupport::TestCase
  setup do
    @membership_type = PaymentEngine::MembershipType.create!(
      name: "Access Test",
      code: "ACCESS_#{SecureRandom.hex(6)}",
      status: "active"
    )
    @user = User.create!(
      name: "Access User",
      email: "access_#{SecureRandom.hex(6)}@example.com",
      password: "password123"
    )
  end

  test "need_membership? returns false when paid access is not required" do
    with_paid_access_required(false) do
      assert_equal false, access.need_membership?
    end
  end

  test "need_membership? returns true when the user has no membership" do
    with_paid_access_required(true) do
      assert_equal true, access.need_membership?
    end
  end

  test "need_membership? returns false with an active paid membership" do
    create_membership(source: "purchase", expires_at: 1.month.from_now)

    with_paid_access_required(true) do
      assert_equal false, access.need_membership?
    end
  end

  test "need_membership? returns false during an active trial" do
    create_membership(source: "trial", expires_at: 10.days.from_now)

    with_paid_access_required(true) do
      assert_equal false, access.need_membership?
    end
  end

  test "need_membership? returns false when the membership has expired" do
    create_membership(source: "purchase", expires_at: 1.day.ago)

    with_paid_access_required(true) do
      assert_equal false, access.need_membership?
    end
  end

  test "need_membership? returns false after the trial expired" do
    create_membership(source: "trial", expires_at: 1.day.ago)

    with_paid_access_required(true) do
      assert_equal false, access.need_membership?
    end
  end

  test "free_membership_used? returns false when the user never started a trial" do
    assert_equal false, access.free_membership_used?
  end

  test "free_membership_used? returns true when the user started a trial" do
    create_membership(source: "trial", expires_at: 10.days.from_now)

    assert_equal true, access.free_membership_used?
  end

  test "free_membership_used? returns true after the trial expired" do
    create_membership(source: "trial", expires_at: 1.day.ago)

    assert_equal true, access.free_membership_used?
  end

  test "free_membership_used? returns false for a paid-only user" do
    create_membership(source: "purchase", expires_at: 1.month.from_now)

    assert_equal false, access.free_membership_used?
  end

  test "free_plan_available? returns true when the user never started a trial" do
    assert_equal true, access.free_plan_available?
  end

  test "free_plan_available? returns false during an active trial" do
    create_membership(source: "trial", expires_at: 10.days.from_now)

    assert_equal false, access.free_plan_available?
  end

  test "free_plan_available? returns false after the trial expired" do
    create_membership(source: "trial", expires_at: 1.day.ago)

    assert_equal false, access.free_plan_available?
  end

  test "free_plan_available? returns false for a paid-only user" do
    create_membership(source: "purchase", expires_at: 1.month.from_now)

    assert_equal false, access.free_plan_available?
  end

  test "free_plan_available? returns false with an expired paid membership" do
    create_membership(source: "purchase", expires_at: 1.day.ago)

    assert_equal false, access.free_plan_available?
  end

  test "access_premium? returns true when paid access is not required" do
    with_paid_access_required(false) do
      assert_equal true, access.access_premium?
    end
  end

  test "access_premium? returns true during an active trial" do
    create_membership(source: "trial", expires_at: 10.days.from_now)

    with_paid_access_required(true) do
      assert_equal true, access.access_premium?
    end
  end

  test "access_premium? returns false after the trial expired" do
    create_membership(source: "trial", expires_at: 1.day.ago)

    with_paid_access_required(true) do
      assert_equal false, access.access_premium?
    end
  end

  test "access_premium? returns true with an active paid membership" do
    create_membership(source: "purchase", expires_at: 1.month.from_now)

    with_paid_access_required(true) do
      assert_equal true, access.access_premium?
    end
  end

  test "access_premium? returns false with an expired paid membership" do
    create_membership(source: "purchase", expires_at: 1.day.ago)

    with_paid_access_required(true) do
      assert_equal false, access.access_premium?
    end
  end

  test "access_premium? returns false without a membership" do
    with_paid_access_required(true) do
      assert_equal false, access.access_premium?
    end
  end

  test "current_membership returns the user membership" do
    membership = create_membership(source: "purchase", expires_at: 1.month.from_now)

    assert_equal membership.id, access.current_membership.id
  end

  test "current_membership returns the newest membership for the user" do
    create_membership(source: "purchase", expires_at: 1.month.ago)
    active = create_membership(source: "purchase", expires_at: 1.month.from_now)

    assert_equal active.id, access.current_membership.id
  end

  test "current_membership returns nil without a membership" do
    assert_nil access.current_membership
  end

  test "membership_expiring_within_days? is true inside the window" do
    create_membership(source: "purchase", expires_at: 4.days.from_now)

    assert_equal true, access.membership_expiring_within_days?(5)
  end

  test "membership_expiring_within_days? is false outside the window" do
    create_membership(source: "purchase", expires_at: 30.days.from_now)

    assert_equal false, access.membership_expiring_within_days?(5)
  end

  test "membership_expiring_within_days? is false after expiry" do
    create_membership(source: "purchase", expires_at: 1.day.ago)

    assert_equal false, access.membership_expiring_within_days?(5)
  end

  test "membership_expiring_within_days? is false without a membership" do
    assert_equal false, access.membership_expiring_within_days?(5)
  end

  test "renewal_prompt? is true after an expired paid membership" do
    create_membership(source: "purchase", expires_at: 1.day.ago)

    with_paid_access_required(true) do
      assert_equal true, access.renewal_prompt?
    end
  end

  test "renewal_prompt? is true after the trial expired" do
    create_membership(source: "trial", expires_at: 1.day.ago)

    with_paid_access_required(true) do
      assert_equal true, access.renewal_prompt?
    end
  end

  test "renewal_prompt? is false with an active paid membership" do
    create_membership(source: "purchase", expires_at: 1.month.from_now)

    with_paid_access_required(true) do
      assert_equal false, access.renewal_prompt?
    end
  end

  test "renewal_prompt? is false during an active trial" do
    create_membership(source: "trial", expires_at: 10.days.from_now)

    with_paid_access_required(true) do
      assert_equal false, access.renewal_prompt?
    end
  end

  test "renewal_prompt? is false when the user never had a membership" do
    with_paid_access_required(true) do
      assert_equal false, access.renewal_prompt?
    end
  end

  test "membership_expiring_within_days? caches the answer per day window" do
    membership = create_membership(source: "purchase", expires_at: 4.days.from_now)
    user_access = PaymentEngine::UserAccess.new(@user.id)
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    assert_equal true, user_access.membership_expiring_within_days?(5)

    membership.update_columns(expires_at: 30.days.from_now)

    assert_equal true, user_access.membership_expiring_within_days?(5)
    assert_equal false, user_access.membership_expiring_within_days?(1)
  ensure
    Rails.cache = original_cache
  end

  test "access questions use independent cache entries for the same user" do
    create_membership(source: "trial", expires_at: 2.days.from_now)
    user_access = PaymentEngine::UserAccess.new(@user.id)
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    with_paid_access_required(true) do
      assert_equal false, user_access.need_membership?
      assert_equal true, user_access.free_membership_used?
      assert_equal true, user_access.access_premium?
    end
  ensure
    Rails.cache = original_cache
  end

  private

  def access
    PaymentEngine::UserAccess.new(@user.id)
  end

  def create_membership(source:, expires_at:)
    PaymentEngine::Membership.create!(
      owner: @user,
      membership_type: @membership_type,
      status: "active",
      source: source,
      starts_at: 1.month.ago,
      expires_at: expires_at
    )
  end

  def with_paid_access_required(required)
    stub_method(PaymentEngine::Configuration, :paid_access_required?, required) do
      yield
    end
  end
end
