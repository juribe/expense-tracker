# frozen_string_literal: true

require "test_helper"

class AlertSettingsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Settings User",
      email: "alert_settings_controller_test@example.com",
      password: "password123"
    )
    sign_in @user
  end

  test "GET /settings/alerts requires authentication" do
    sign_out @user
    get alert_settings_path
    assert_redirected_to new_user_session_path
  end

  test "GET /settings/alerts creates the preferences row with defaults and renders the three toggles" do
    get alert_settings_path

    assert_response :success
    prefs = @user.reload.alert_preference
    assert prefs.present?
    assert prefs.budget_threshold_enabled?
    assert prefs.budget_exceeded_enabled?
    assert_not prefs.spending_increase_enabled?
    assert_select "form[action='#{alert_settings_path}']"
    assert_select "input[type=checkbox]", count: 3
  end

  test "PATCH /settings/alerts saves the toggles" do
    patch alert_settings_path, params: {
      alert_preference: {
        budget_threshold_enabled: false,
        budget_exceeded_enabled: true,
        spending_increase_enabled: true
      }
    }

    assert_redirected_to alert_settings_path
    prefs = @user.reload.alert_preference
    assert_not prefs.budget_threshold_enabled?
    assert prefs.budget_exceeded_enabled?
    assert prefs.spending_increase_enabled?
  end

  test "PATCH /settings/alerts renders the form again when the update fails" do
    prefs = @user.alert_prefs

    stub_method(prefs, :update, false) do
      patch alert_settings_path, params: { alert_preference: { budget_threshold_enabled: false } }
    end

    assert_response :unprocessable_entity
    assert prefs.reload.budget_threshold_enabled?
  end
end
