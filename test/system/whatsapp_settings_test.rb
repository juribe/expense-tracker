# frozen_string_literal: true

require "application_system_test_case"

# Browser behavior of Settings → Gastos por WhatsApp: the two association
# states, the primary "Enviar mensaje" action, privacy/instructions blocks and
# the mobile single-column layout.
class WhatsappSettingsTest < ApplicationSystemTestCase
  setup do
    @user = User.create!(name: "WhatsApp Settings", email: "whatsapp_settings_system@example.com",
                         password: "password123")
    @user.confirm
    ENV["WHATSAPP_BUSINESS_NUMBER"] = "573001112233"
    page.current_window.resize_to(1400, 1000)
  end

  teardown do
    ENV.delete("WHATSAPP_BUSINESS_NUMBER")
    page.current_window.resize_to(1400, 1000)
  rescue StandardError
    # The driver may have restarted before mounting the page.
  end

  test "disconnected page leads with the initial message action and privacy" do
    sign_in
    visit whatsapp_settings_path

    assert_selector ".whatsapp-status.is-off", text: "Gastos por WhatsApp inactivos"
    assert_selector "a[data-connect-action]", text: "Enviar mensaje a Yogasto"
    assert_text "Registra tus gastos por WhatsApp"
    assert_text "Tu privacidad está protegida"
    assert_text "El mensaje inicial solo necesitas enviarlo una vez."
    assert_selector ".whatsapp-example", count: 3
    assert_selector "section.whatsapp-instructions.card"
    assert_text "Solo se hace la primera vez"
    assert_selector ".whatsapp-steps li", count: 3
  end

  test "connected page shows the linked number and the secondary disconnect action" do
    identity = WhatsappIdentity.create!(phone_number: "573001234567", claimed_by_user: @user,
                                       claimed_at: 1.day.ago)
    WhatsappConnection.create!(user: @user, whatsapp_identity: identity, connected_at: 1.day.ago)

    sign_in
    visit whatsapp_settings_path

    assert_selector ".whatsapp-status.is-on", text: "Gastos por WhatsApp activos"
    assert_text "Recibiendo tus gastos por WhatsApp"
    assert_text "+57 300 123 4567"
    assert_selector "button", text: "Desconectar WhatsApp"
    assert_no_selector "a[data-connect-action]"
  end

  test "mobile stacks the sections in one column without horizontal overflow" do
    page.current_window.resize_to(390, 1200)
    sign_in
    visit whatsapp_settings_path

    assert_equal 1, grid_columns(".whatsapp-state-grid")
    assert_equal 1, grid_columns(".whatsapp-examples")
    assert_equal 1, grid_columns(".whatsapp-steps")

    scroll_width = page.evaluate_script("document.documentElement.scrollWidth")
    client_width = page.evaluate_script("document.documentElement.clientWidth")
    assert_operator scroll_width, :<=, client_width + 1
  end

  private

  def grid_columns(selector)
    page.evaluate_script(
      "getComputedStyle(document.querySelector(#{selector.to_json})).gridTemplateColumns.split(' ').length"
    )
  end

  def sign_in
    visit new_user_session_path
    fill_in "user_email", with: @user.email
    fill_in "user_password", with: "password123"
    click_button I18n.t("auth.sign_in", default: "Iniciar sesión")
    assert_selector "aside.left-sidebar", wait: 10
  end
end
