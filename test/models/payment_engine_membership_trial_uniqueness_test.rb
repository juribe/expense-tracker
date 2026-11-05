# frozen_string_literal: true

require "test_helper"

class PaymentEngineMembershipTrialUniquenessTest < ActiveSupport::TestCase
  setup do
    @membership_type = PaymentEngine::MembershipType.create!(
      name: "Trial Uniqueness",
      code: "TRIAL_UNIQUE_#{SecureRandom.hex(6)}",
      status: "active"
    )
    @user = User.create!(
      name: "Trial Uniqueness User",
      email: "trial-unique-#{SecureRandom.hex(6)}@example.com",
      password: "password123"
    )
  end

  test "a user can have at most one trial membership" do
    create_trial_membership

    duplicate = build_trial_membership

    assert_not duplicate.valid?
    assert_includes duplicate.errors.full_messages, "La prueba gratuita ya fue utilizada por este usuario"
    assert_raises(ActiveRecord::RecordInvalid) { duplicate.save! }
  end

  test "an expired trial still blocks a new trial" do
    create_trial_membership(expires_at: 1.day.ago)

    duplicate = build_trial_membership

    assert_not duplicate.valid?
    assert_raises(ActiveRecord::RecordInvalid) { duplicate.save! }
  end

  test "granting a second trial through the service fails" do
    create_trial_membership

    result = PaymentEngine::Memberships::Grant.call(
      owner: @user,
      membership_type: @membership_type,
      source: "trial"
    )

    assert_not result.success?
    assert_includes result.errors, "La prueba gratuita ya fue utilizada por este usuario"
  end

  private

  def create_trial_membership(expires_at: 1.month.from_now)
    PaymentEngine::Membership.create!(
      owner: @user,
      membership_type: @membership_type,
      status: "active",
      source: "trial",
      starts_at: 1.day.ago,
      expires_at: expires_at
    )
  end

  def build_trial_membership
    PaymentEngine::Membership.new(
      owner: @user,
      membership_type: @membership_type,
      status: "active",
      source: "trial",
      starts_at: Time.current,
      expires_at: 1.month.from_now
    )
  end
end
