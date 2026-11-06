# frozen_string_literal: true

require "application_system_test_case"

# End-to-end behavior of the public Contáctanos form: reason selection,
# AJAX submission states and the mobile layout.
class ContactFormTest < ApplicationSystemTestCase
  include PublicCmsTestSupport

  setup do
    create_maglev_site!
    page.current_window.resize_to(1400, 1000)
  end

  teardown do
    page.current_window.resize_to(1400, 1000)
  rescue StandardError
    # El driver puede haberse reiniciado si el test falló antes de montar la página.
  end

  test "seleccionar un motivo actualiza el formulario" do
    visit "/contact"

    assert_selector "[data-contact-reason='Tengo una pregunta'][aria-pressed='true']"

    find("[data-contact-reason='Necesito soporte']").click

    assert_equal "Necesito soporte", find("#contact_message_subject").value
    assert_selector "[data-contact-reason='Necesito soporte'][aria-pressed='true']"
    assert_selector "[data-contact-reason='Tengo una pregunta'][aria-pressed='false']"
  end

  test "el envío exitoso muestra confirmación y limpia el formulario" do
    visit "/contact"

    fill_in "contact_message_name", with: "Ana Pérez"
    fill_in "contact_message_email", with: "ana@example.com"
    select "Necesito soporte", from: "contact_message_subject"
    fill_in "contact_message_message", with: "No puedo registrar un gasto."

    find("[data-contact-submit]").click

    assert_selector "[data-contact-status].is-success", text: "¡Mensaje enviado!"
    assert_equal "", find("#contact_message_name").value
    assert_equal "", find("#contact_message_email").value
    assert_equal "", find("#contact_message_message").value
    assert_no_selector "[data-contact-submit][disabled]"
  end

  test "un error del servidor conserva los datos" do
    visit "/contact"

    page.execute_script(<<~JS)
      const form = document.querySelector("[data-contact-form]");
      form.querySelectorAll("[required]").forEach((field) => field.removeAttribute("required"));
      form.querySelector("#contact_message_email").type = "text";
    JS

    fill_in "contact_message_name", with: "Ana Pérez"
    fill_in "contact_message_email", with: "no-es-un-correo"
    select "Necesito soporte", from: "contact_message_subject"
    fill_in "contact_message_message", with: "Mensaje que debe conservarse"

    find("[data-contact-submit]").click

    assert_selector "[data-contact-status].is-error", text: /No pudimos enviar/
    assert_equal "Ana Pérez", find("#contact_message_name").value
    assert_equal "no-es-un-correo", find("#contact_message_email").value
    assert_equal "Mensaje que debe conservarse", find("#contact_message_message").value
    assert_no_selector "[data-contact-submit][disabled]"
  end

  test "la página no desborda horizontalmente en móvil" do
    page.current_window.resize_to(390, 844)
    visit "/contact"

    hero_display = page.evaluate_script(
      "getComputedStyle(document.querySelector('.institutional-hero-grid')).display"
    )
    assert_equal "grid", hero_display

    hero_columns = page.evaluate_script(
      "getComputedStyle(document.querySelector('.institutional-hero-grid')).gridTemplateColumns.split(' ').length"
    )
    assert_equal 1, hero_columns

    contact_display = page.evaluate_script(
      "getComputedStyle(document.querySelector('.contact-grid')).display"
    )
    assert_equal "grid", contact_display

    contact_columns = page.evaluate_script(
      "getComputedStyle(document.querySelector('.contact-grid')).gridTemplateColumns.split(' ').length"
    )
    assert_equal 1, contact_columns

    copy_bottom = page.evaluate_script(
      "document.querySelector('.institutional-hero-copy').getBoundingClientRect().bottom"
    )
    art_top = page.evaluate_script(
      "document.querySelector('.institutional-hero-art').getBoundingClientRect().top"
    )
    assert_operator art_top, :>=, copy_bottom - 1

    scroll_width = page.evaluate_script("document.documentElement.scrollWidth")
    client_width = page.evaluate_script("document.documentElement.clientWidth")
    assert_operator scroll_width, :<=, client_width + 1

    font_size = page.evaluate_script(
      "parseFloat(getComputedStyle(document.querySelector('#contact_message_name')).fontSize)"
    )
    assert_operator font_size, :>=, 16

    honeypot_left = page.evaluate_script(
      "document.querySelector('#contact_message_website').getBoundingClientRect().left"
    )
    assert_operator honeypot_left, :<, 0
  end
end
