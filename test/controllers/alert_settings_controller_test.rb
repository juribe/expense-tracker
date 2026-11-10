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

  test "GET /settings/alerts renders the grouped alert cards with visual percentages" do
    get alert_settings_path

    assert_response :success
    assert_select ".alert-settings-group", count: 2
    assert_select ".alert-settings-row", count: 3
    assert_select ".alert-settings-badge", text: "80%"
    assert_select ".alert-settings-badge", text: "35%"
    assert_select ".alert-settings-note",
                  text: /Recibirás cada alerta solo una vez por mes y por categoría/
    assert_select "form button[type=submit]", text: /Guardar/
    assert_select "form a[href='#{alerts_path}']", text: /Cancelar/
  end

  test "GET /settings/alerts keeps each switch bound to its preference attribute" do
    get alert_settings_path

    assert_select "input[type=checkbox][name='alert_preference[budget_threshold_enabled]']", count: 1
    assert_select "input[type=checkbox][name='alert_preference[budget_exceeded_enabled]']", count: 1
    assert_select "input[type=checkbox][name='alert_preference[spending_increase_enabled]']", count: 1
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

  test "the sidebar links to the alert settings page from the settings section" do
    get alert_settings_path

    assert_select "aside.left-sidebar a[href='#{alert_settings_path}'] span",
                  text: I18n.t("nav.configure_alerts", default: "Configurar alertas")
  end

  test "the alert preferences page no longer links to the WhatsApp configuration" do
    get alert_settings_path

    # The sidebar keeps its own WhatsApp entry; the page itself must not.
    assert_select "a[href='#{whatsapp_settings_path}']", count: 1
  end
end
