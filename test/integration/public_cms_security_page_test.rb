# frozen_string_literal: true

require "test_helper"

# Public security page rendered from the shared Maglev institutional sections.
class PublicCmsSecurityPageTest < ActionDispatch::IntegrationTest
  include PublicCmsTestSupport

  setup do
    @site = create_maglev_site!
  end

  test "renderiza el hero, la navegación y el footer compartidos" do
    get "https://yogasto.co/seguridad"

    assert_response :success
    assert_match "<title>Seguridad y protección de datos | Yogasto</title>", response.body
    assert_select "h1", count: 1, text: /Tu información financiera merece cuidado/
    assert_select "section.institutional-hero--lavender", 1
    assert_select ".institutional-eyebrow", text: /Seguridad y privacidad/
    assert_select ".security-shield-card", 1
    assert_select ".security-float", count: 2
    assert_select ".institutional-hero-note", text: /Información clara sobre nuestras prácticas/
    assert_select "footer.site-footer", 1
  end

  test "el compromiso muestra solo prácticas verificadas" do
    get "https://yogasto.co/seguridad"

    assert_select "#compromiso .feature", count: 3
    assert_match "OVHcloud", response.body
    assert_match "tablas de procesamiento", response.body
    assert_match(/no almacena números ni datos completos de tarjetas/i, response.body)
    refute_match "certificación ISO", response.body
    refute_match "riesgo cero garantizado", response.body
  end

  test "una tarjeta de compromiso oculta no se renderiza" do
    Maglev::I18n.with_locale("es") do
      page = Maglev::Page.by_path("seguridad").first
      sections = page.sections
      security_section = sections.find { |section| section["type"] == "security" }
      block = security_section["blocks"].first
      visible_setting = block["settings"].find { |setting| setting["id"] == "visible" }
      visible_setting["value"] = false

      page.sections = sections
      page.save!
      Maglev::PublishService.call(site: @site, page: page)

      persisted = page.reload.sections
        .find { |section| section["type"] == "security" }
        .dig("blocks", 0, "settings")
        .find { |setting| setting["id"] == "visible" }
      assert_equal false, persisted["value"]

      published = page.sections_content_stores.find_by(published: true)
        .sections_translations["es"]
        .find { |section| section["type"] == "security" }
        .dig("blocks", 0, "settings")
        .find { |setting| setting["id"] == "visible" }
      assert_equal false, published["value"]
    end

    get "https://yogasto.co/seguridad"

    assert_select "#compromiso .feature", count: 2
  end

  test "el proceso de correos explica las cinco etapas y la eliminación temporal" do
    get "https://yogasto.co/seguridad"

    assert_select "#correos .security-step", count: 5
    assert_select "#correos .security-step", text: /Recepción del correo/
    assert_select "#correos .security-step", text: /Almacenamiento temporal/
    assert_select "#correos .security-step", text: /Extracción de información/
    assert_select "#correos .security-step", text: /Eliminación del contenido original/
    assert_select "#correos .security-step", text: /Conservación del movimiento/
    assert_match "se elimina de las tablas temporales", response.body
    assert_match "datos estructurados", response.body
  end

  test "qué guardamos y qué no separa los datos y aclara el alcance técnico" do
    get "https://yogasto.co/seguridad"

    assert_select "#datos .security-data-panel", count: 2
    assert_select ".security-data-panel--kept li", count: 2
    assert_select ".security-data-panel--not_kept li", count: 2
    assert_match "contenido original del correo", response.body
    assert_match "registros técnicos", response.body
    assert_match "respaldos", response.body
  end

  test "las buenas prácticas no prometen funciones inexistentes" do
    get "https://yogasto.co/seguridad"

    assert_select "#practicas .security-practice", count: 3
    assert_match "contraseña segura", response.body
    assert_match "No compartas tus credenciales", response.body
    refute_match "cerrar sesiones", response.body
    refute_match "dispositivos conectados", response.body
  end

  test "las preguntas frecuentes usan acordeones nativos" do
    get "https://yogasto.co/seguridad"

    assert_select "#preguntas details", count: 5
    assert_select "#preguntas summary", count: 5
    assert_select "#preguntas details[open]", count: 0
    assert_match "¿Yogasto guarda el contenido de mis correos?", response.body
    assert_match "¿Yogasto almacena los datos de mi tarjeta de crédito?", response.body
  end

  test "configura SEO, canonical y una sola URL pública" do
    get "https://yogasto.co/seguridad"

    assert_select "meta[name='description'][content='Conoce cómo Yogasto procesa tu información financiera, gestiona temporalmente los correos electrónicos y cuida tus datos.']", 1
    assert_select "link[rel='canonical'][href='https://yogasto.co/seguridad']", 1
    assert_select "meta[property='og:title'][content='Seguridad y protección de datos']", 1
    assert_select "meta[property='og:description']", 1
    assert_select "link[href*='security']", minimum: 1
  end

  test "el CTA y el footer usan las rutas institucionales actuales" do
    get "https://yogasto.co/seguridad"

    assert_select "section.security-cta a[href='/contact']", 1
    assert_select "footer.site-footer a[href='/contact']", minimum: 1
    assert_select "footer.site-footer a[href='/seguridad']", minimum: 1
    assert_select "footer.site-footer a[href='/terminos-y-condiciones']", minimum: 1
  end

  test "la página es pública y no exige autenticación" do
    get "https://yogasto.co/seguridad"

    assert_response :success
    assert_select "a[href='/users/sign_in']", minimum: 1
  end

  test "la sección compartida conserva el ancla de la home" do
    get "https://yogasto.co/"

    assert_response :success
    assert_select "#seguridad .feature", count: 3
  end

  test "/security redirige de forma permanente a /seguridad" do
    get "https://yogasto.co/security"

    assert_response :moved_permanently
    assert_redirected_to "/seguridad"
  end
end
