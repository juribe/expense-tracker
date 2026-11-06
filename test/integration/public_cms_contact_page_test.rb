# frozen_string_literal: true

require "test_helper"

# Public Contáctanos page served by Maglev. The page must be administrable,
# reuse the sitewide navigation/footer and expose a real contact form.
class PublicCmsContactPageTest < ActionDispatch::IntegrationTest
  include PublicCmsTestSupport

  setup do
    create_maglev_site!
  end

  test "GET /contact sirve la página publicada con todas sus secciones" do
    get "https://yogasto.co/contact"

    assert_response :success
    assert_match "Estamos para ayudarte", response.body
    assert_match "Hablemos.", response.body
    assert_match "Estamos aquí para ayudarte", response.body
    assert_match "¿En qué podemos ayudarte?", response.body
    assert_match "¿Buscas una respuesta rápida?", response.body
    assert_match "También estamos aquí", response.body
    assert_match "Tus finanzas, más claras.", response.body
    assert_select "section.institutional-hero", 1
    assert_select "section.contact-section", 1
    assert_select "section.institutional-links", 1
    assert_select "section.institutional-content", 1
    assert_select "form[data-contact-form][action='/contact']", 1
    assert_select "nav .brand", 1
    assert_select "footer.site-footer", 1
  end

  test "SEO: título, meta description, canonical, robots y un solo H1" do
    get "https://yogasto.co/contact"

    assert_response :success
    assert_match "<title>Contáctanos | Yogasto</title>", response.body
    assert_match 'name="description" content="¿Tienes preguntas o necesitas ayuda con Yogasto? Escríbenos, estaremos encantados de ayudarte."', response.body
    assert_match 'rel="canonical" href="https://yogasto.co/contact"', response.body
    assert_match 'name="robots" content="index,follow"', response.body
    assert_select "h1", count: 1
    assert_select "h1", text: /Hablemos/
    assert_select "h2", text: /¿En qué podemos ayudarte?/
    assert_select "h2", text: /También estamos aquí/
  end

  test "el formulario tiene campos accesibles y el honeypot oculto" do
    get "https://yogasto.co/contact"

    assert_select "label[for='contact_message_name']", text: /Nombre/i
    assert_select "label[for='contact_message_email']", text: /Correo/i
    assert_select "label[for='contact_message_subject']", text: /Motivo/i
    assert_select "label[for='contact_message_message']", text: /Mensaje/i

    assert_select "#contact_message_name[required]"
    assert_select "#contact_message_email[type='email'][required]"
    assert_select "#contact_message_subject[required]"
    assert_select "#contact_message_message[required]"

    expected_subjects = [
      "Tengo una pregunta",
      "Necesito soporte",
      "Quiero compartir una idea",
      "Consulta sobre mi membresía",
      "Otro motivo"
    ]
    assert_equal expected_subjects, css_select("#contact_message_subject option").map { |option| option["value"] }

    assert_select "form[aria-labelledby='contact-form-title']"
    assert_select "button[data-contact-reason]", count: 3
    assert_select "button[data-contact-reason][aria-pressed='true']", 1
    assert_select "#contact_message_website[tabindex='-1'][aria-hidden='true']"
    assert_select "[data-contact-status][role='status'][aria-live='polite']", 1
    assert_select "[data-contact-submit][data-sending-label]"
  end

  test "los enlaces de ayuda, privacidad y seguridad apuntan a páginas Maglev" do
    get "https://yogasto.co/contact"

    assert_select "a[href='/help']", minimum: 2
    assert_select "a[href='/privacy']", minimum: 1
    assert_select "a[href='/security']", minimum: 1
    assert_select "footer.site-footer a[href='/contact']", minimum: 1
    assert_select "footer.site-footer a[href='/help']", minimum: 1
    assert_select "footer.site-footer a[href='/privacy']", minimum: 1
    assert_select "footer.site-footer a[href='/terms']", minimum: 1
    assert_select "footer.site-footer a[href='/security']", minimum: 1
  end

  test "la página existe y se administra desde Maglev" do
    page = Maglev::Page.by_path("contact").first

    assert_not_nil page
    assert_includes page.sections.map { |section| section["type"] }, "institutional_hero"
    assert_includes page.sections.map { |section| section["type"] }, "contact"
    assert_includes page.sections.map { |section| section["type"] }, "link_cards"
    assert_includes page.sections.map { |section| section["type"] }, "institutional_content"
  end

  test "un cambio en borrador no se publica hasta publicar la página" do
    Maglev::I18n.with_locale("es") do
      page = Maglev::Page.by_path("contact").first
      hero = page.sections.find { |section| section["type"] == "institutional_hero" }
      eyebrow = hero["settings"].find { |setting| setting["id"] == "eyebrow" }
      eyebrow["value"] = "Borrador de contacto"
      page.save!
    end

    get "https://yogasto.co/contact"
    assert_response :success
    refute_match "Borrador de contacto", response.body

    Maglev::I18n.with_locale("es") do
      page = Maglev::Page.by_path("contact").first
      Maglev::PublishService.call(site: Maglev::Site.first, page: page)
    end

    get "https://yogasto.co/contact"
    assert_response :success
    assert_match "Borrador de contacto", response.body
  end
end
