# frozen_string_literal: true

require "application_system_test_case"

class EmailSourcesSetupFlowTest < ApplicationSystemTestCase
  driven_by :selenium_chrome_headless

  setup do
    @user = User.create!(
      name: "Setup Flow",
      email: "setup_flow_#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    @user.confirm
  end

  test "progresses from add through accepting a non-Gmail sender without a link" do
    sign_in @user
    visit email_sources_path

    source = @user.email_sources.create!(
      source_type: "forwarding",
      email: "jse.uribe@outlook.com",
      status: "pending_setup"
    )

    assert_selector "#initialActions", visible: :visible
    assert_no_selector "#nextActions", visible: :visible
    assert_no_selector "#setupInstructions", visible: :visible

    click_button "Agregar redirección"

    assert_selector "#setupInstructions", visible: :visible
    assert_selector "#nextActions", visible: :visible
    assert_no_selector "#initialActions", visible: :visible

    within "#setupInstructions" do
      assert_text "Configura el reenvío de correos"
      assert_text "Si usas Gmail"
      assert_text "Copia tu dirección personalizada y agrégala en Gmail"
      assert_text "Gmail enviará automáticamente un correo de verificación a nuestra aplicación"
      assert_text "Cuando termines, pulsa «Ya configuré el reenvío · Buscar correo»"
      assert_text "Si usas otro proveedor"
      assert_text "Envíanos un correo de prueba"
      assert_text "Importante: el correo de prueba debe enviarse desde la cuenta que quieres registrar"
      assert_link "Ayuda oficial de Gmail", href: "https://support.google.com/mail/answer/10957"
    end

    click_button "Ya configuré el reenvío · Buscar correo"

    assert_selector "#sourceDetected.show", wait: 10
    within "#sourceDetected" do
      assert_text "jse.uribe@outlook.com"
      assert_text "Acepta el remitente"
    end
    assert_no_selector "#detected.show"
    assert_no_selector "#openLinkBtn", visible: :visible

    click_button "Aceptar remitente"

    assert_text "¡Remitente aceptado!", wait: 10
    assert_equal "active", source.reload.status
    assert_selector ".source-row[data-source-id='#{source.id}']", count: 1
    within ".source-row[data-source-id='#{source.id}']" do
      assert_text "Activa"
      assert_no_button "Aceptar"
      assert_equal "¿Eliminar esta redirección? Esta acción no se puede deshacer.",
                   find("form.es-delete-form")["data-turbo-confirm"]
    end
    assert_selector "#step3.active"
  end

  test "shows a safe Gmail verification link and activates the source" do
    source = @user.email_sources.create!(
      source_type: "forwarding",
      email: "bank@example.com",
      status: "pending_verification"
    )
    verification = @user.email_forwarding_verifications.create!(
      email_source: source,
      confirmation_url: "https://mail-settings.google.com/mail/vf-abc123",
      sender_email: "forwarding-noreply@google.com",
      subject: "Confirmación de reenvío de Gmail: recibir correo de bank@example.com",
      expires_at: 1.day.from_now
    )

    sign_in @user
    visit email_sources_path

    click_button "Agregar redirección"
    click_button "Ya configuré el reenvío · Buscar correo"

    assert_selector "#detected.show", wait: 10
    within "#detected" do
      assert_text "bank@example.com"
      assert_text "Confirmación de reenvío de Gmail"
      assert_text "https://mail-settings.google.com/mail/vf-abc123"
      assert_button "Abrir enlace de confirmación"
      assert_button "Copiar enlace"
    end
    assert_no_selector "#sourceDetected.show"

    click_button "Ya completé la confirmación"

    assert_text "¡Redirección configurada!", wait: 10
    assert_equal "active", source.reload.status
    assert verification.reload.consumed?
    assert_selector ".source-row[data-source-id='#{source.id}']", count: 1
    within ".source-row[data-source-id='#{source.id}']" do
      assert_text "Activa"
      assert_no_button "Aceptar"
    end
    assert_selector "#step3.active"
  end

  test "asks for confirmation before deleting a source" do
    source = @user.email_sources.create!(
      source_type: "forwarding",
      email: "bank@example.com",
      status: "active"
    )

    sign_in @user
    visit email_sources_path

    row_selector = ".source-row[data-source-id='#{source.id}']"
    message = "¿Eliminar esta redirección? Esta acción no se puede deshacer."

    assert_selector row_selector

    dismiss_confirm message do
      within row_selector do
        click_button "Eliminar"
      end
    end

    assert_selector row_selector
    assert EmailSource.exists?(source.id)

    accept_confirm message do
      within row_selector do
        click_button "Eliminar"
      end
    end

    assert_no_selector row_selector
    refute EmailSource.exists?(source.id)
  end

  private

  def sign_in(user)
    visit new_user_session_path
    fill_in "user_email", with: user.email
    fill_in "user_password", with: "password123"
    click_button I18n.t("auth.sign_in")
  end
end
