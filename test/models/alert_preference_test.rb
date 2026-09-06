# frozen_string_literal: true

require "test_helper"

class AlertPreferenceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      name: "Prefs User",
      email: "alert_preference_test@example.com",
      password: "password123"
    )
  end

  test "User#alert_prefs builds and persists defaults on first access" do
    assert_not AlertPreference.exists?(user_id: @user.id)

    prefs = @user.alert_prefs

    assert prefs.persisted?
    assert prefs.budget_threshold_enabled?
    assert prefs.budget_exceeded_enabled?
    assert_not prefs.spending_increase_enabled?
    assert_equal @user.id, prefs.user_id
  end

  test "User#alert_prefs returns the same row on subsequent access" do
    first = @user.alert_prefs
    second = @user.alert_prefs

    assert_equal first.id, second.id
    assert_equal 1, AlertPreference.where(user_id: @user.id).count
  end

  test "user can disable the budget toggles" do
    prefs = @user.alert_prefs
    prefs.update!(budget_threshold_enabled: false, budget_exceeded_enabled: false)

    assert_not prefs.reload.budget_threshold_enabled?
    assert_not prefs.reload.budget_exceeded_enabled?
  end

  test "destroying the user removes its preferences" do
    @user.alert_prefs
    @user.destroy!
    assert_not AlertPreference.exists?(user_id: @user.id)
  end
end
