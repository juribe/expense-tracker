# frozen_string_literal: true

require "test_helper"

class UserMoneyTrackingTest < ActiveSupport::TestCase
  test "users created outside the sign-up flow keep the legacy advanced behavior" do
    user = User.create!(name: "Legacy User", email: "legacy_tracking@example.com", password: "password123")

    assert_equal "detailed", user.money_tracking_mode
    assert user.money_tracking_detailed?
    refute user.money_tracking_simple?
    assert user.money_tracking_mode_selected?
  end

  test "a user created through sign-up starts in simple mode without a confirmed selection" do
    user = User.create!(
      name: "New User",
      email: "new_tracking@example.com",
      password: "password123",
      registration_form: true,
      terms_accepted: "1",
      privacy_accepted: "1"
    )

    assert_equal "simple", user.money_tracking_mode
    assert user.money_tracking_simple?
    refute user.money_tracking_mode_selected?
    assert_equal "general", user.general_money_source.kind
  end

  test "General is created once per user and reused" do
    user = User.create!(name: "General User", email: "general_user_tracking@example.com", password: "password123")

    assert_difference "MoneySource.count", 1 do
      @general = user.general_money_source
    end

    assert_no_difference "MoneySource.count" do
      assert_equal @general.id, user.general_money_source.id
      assert_equal @general.id, user.ensure_general_money_source!.id
    end
  end

  test "the default money source must belong to the user" do
    user = User.create!(name: "Default Source User", email: "default_source_tracking@example.com", password: "password123")
    other = User.create!(name: "Other Default", email: "other_default_tracking@example.com", password: "password123")
    foreign = other.money_sources.create!(name: "Ajena", kind: "account")

    user.default_money_source = foreign

    refute user.valid?
    assert user.errors[:default_money_source].any?
  end

  test "the mode only accepts simple or detailed" do
    user = User.create!(name: "Mode Validation", email: "mode_validation@example.com", password: "password123")

    user.money_tracking_mode = "other"

    refute user.valid?
    assert user.errors[:money_tracking_mode].any?
  end
end
