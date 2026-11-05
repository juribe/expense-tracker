# frozen_string_literal: true

require "test_helper"

class PaymentEngineMembershipTypeCounterCacheTest < ActiveSupport::TestCase
  setup do
    @membership_type = PaymentEngine::MembershipType.create!(
      name: "Counter Cache",
      code: "COUNTER_#{SecureRandom.hex(6)}",
      status: "active"
    )
    @user = User.create!(
      name: "Counter Cache User",
      email: "counter-cache-#{SecureRandom.hex(6)}@example.com",
      password: "password123"
    )
  end

  test "payment options counter cache tracks creates and destroys" do
    assert_equal 0, @membership_type.payment_options_count

    option = create_payment_option

    assert_equal 1, @membership_type.reload.payment_options_count

    option.destroy!

    assert_equal 0, @membership_type.reload.payment_options_count
  end

  test "memberships counter cache tracks creates and destroys" do
    assert_equal 0, @membership_type.memberships_count

    membership = create_membership

    assert_equal 1, @membership_type.reload.memberships_count

    membership.destroy!

    assert_equal 0, @membership_type.reload.memberships_count
  end

  test "association size uses the counter cache values" do
    create_payment_option
    create_membership

    @membership_type.reload

    assert_equal 1, @membership_type.payment_options.size
    assert_equal 1, @membership_type.memberships.size
  end

  private

  def create_payment_option
    PaymentEngine::PaymentOption.create!(
      membership_type: @membership_type,
      name: "Mensual Counter",
      price: 14_900,
      currency: "COP",
      mode: "recurring",
      interval: "month",
      interval_count: 1,
      access_duration_count: 1,
      access_duration_unit: "month",
      status: "active"
    )
  end

  def create_membership
    PaymentEngine::Membership.create!(
      owner: @user,
      membership_type: @membership_type,
      status: "active",
      source: "manual",
      starts_at: Time.current,
      expires_at: 1.month.from_now
    )
  end
end
