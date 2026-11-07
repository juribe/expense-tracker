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
    assert_select "h1", count: 1, text: /Tu información financiera merece protección/
    assert_select "section.institutional-hero--lavender", 1
    assert_select ".institutional-eyebrow", text: /SEGURIDAD Y TRANSPARENCIA/
    assert_select ".security-shield-card", 1
    assert_select "footer.site-footer", 1
  end

  test "la protección de la cuenta explica contraseña, passkeys y TOTP" do
    get "https://yogasto.co/seguridad"

    assert_select "#cuenta .feature", count: 3
    assert_match "Passkeys", response.body
    assert_match "Códigos TOTP", response.body
    assert_match "son opcionales", response.body
    refute_match "biometría se envía", response.body
  end

  test "la protección de la información muestra medidas verificadas" do
    get "https://yogasto.co/seguridad"

    assert_select "#proteccion .security-practice", count: 6
    assert_match "HTTPS", response.body
    assert_match "cifrado en reposo", response.body
    assert_match "no incorpora cookies de analítica", response.body
    refute_match "100 %", response.body
    refute_match "riesgo cero garantizado", response.body
  end

  test "el procesamiento explica datos, correos, WhatsApp, archivos e IA" do
    get "https://yogasto.co/seguridad"

    assert_select "#procesamiento .security-step", count: 6
    assert_select "#procesamiento .security-step", text: /Gastos, ingresos y movimientos/
    assert_select "#procesamiento .security-step", text: /Correos y Gmail/
    assert_select "#procesamiento .security-step", text: /WhatsApp/
    assert_select "#procesamiento .security-step", text: /Archivos y extractos bancarios/
    assert_select "#procesamiento .security-step", text: /Inteligencia artificial/
    assert_select "#procesamiento .security-step", text: /Telemetría y registros de IA/
    assert_match "Mistral", response.body
    assert_match "OpenRouter", response.body
    assert_match "plan Pro", response.body
  end

  test "el control de la información explica las acciones del usuario y los backups" do
    get "https://yogasto.co/seguridad"

    assert_select "#control .security-data-panel", count: 2
    assert_match "Cerrar tu cuenta", response.body
    assert_match "copias de seguridad", response.body
  end

  test "infraestructura y proveedores coinciden con la Política de privacidad" do
    get "https://yogasto.co/seguridad"

    assert_select "#infraestructura details", count: 7
    assert_match "OVHcloud", response.body
    assert_match "Canadá", response.body
    assert_match "ePayco", response.body
    assert_match "Cloudflare", response.body
    assert_select "#infraestructura a[href='/privacidad']", 1
  end

  test "el canal para reportar problemas de seguridad está visible" do
    get "https://yogasto.co/seguridad"

    assert_select "#reportar", 1
    assert_match "¿Encontraste algo sospechoso?", response.body
    assert_select "section.security-cta a[href='mailto:hola@yogasto.co']", 1
  end

  test "configura SEO, canonical y una sola URL pública" do
    get "https://yogasto.co/seguridad"

    assert_select "meta[name='description'][content='Conoce cómo Yogasto protege tu cuenta y tu información, cómo procesa los datos y qué puedes hacer para mantener el control.']", 1
    assert_select "link[rel='canonical'][href='https://yogasto.co/seguridad']", 1
    assert_select "meta[property='og:title'][content='Seguridad y protección de datos']", 1
    assert_select "meta[property='og:description']", 1
    assert_select "link[href*='security']", minimum: 1
  end

  test "una tarjeta de protección oculta no se renderiza" do
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
    end

    get "https://yogasto.co/seguridad"

    assert_select "#cuenta .feature", count: 2
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
