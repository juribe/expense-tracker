# frozen_string_literal: true

require "test_helper"

# The public marketing home is served by the Maglev engine at "/" (CMS home
# page); these tests cover the public rendering, SEO metadata and the
# historical redirect of signed-in users to their dashboard.
class PublicCmsHomeTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PublicCmsTestSupport

  setup do
    create_maglev_site!
  end

  test "GET / serves the published CMS home for visitors" do
    get "https://yogasto.co/"

    assert_response :success
    assert_match "Tus finanzas", response.body
    assert_match "por fin en orden", response.body
    assert_match "Mucho más que anotar gastos", response.body
    assert_match "De una notificación a un gasto", response.body
    assert_match "TU MENSAJE", response.body
    assert_match "Chat Financiero", response.body
    assert_match "Conexión protegida", response.body
    assert_match "Ver todos los precios", response.body
    assert_match "Deja de preguntarte a dónde se fue tu dinero", response.body
    # Header and footer are shared site-scoped sections, not page duplicates
    assert_select "nav .brand", 1
    assert_select "footer.site-footer .footer-col", 3
  end

  test "el Centro de ayuda vive en el footer y no en el header" do
    get "https://yogasto.co/"

    assert_select "nav .nav-links a[href='/ayuda']", 0
    assert_select "footer.site-footer a[href='/ayuda']", minimum: 1
  end

  test "the home renders the interactive demo with its four tabs" do
    get "https://yogasto.co/"

    tabs = assert_select ".flow-tab", count: 4
    assert_match "Correo", response.body
    assert_match "WhatsApp imagen", response.body
    assert_match "PASO 1", response.body
    assert_select "article.demo-flow.active", 1
  end

  test "home renders the SEO metadata server-side" do
    get "https://yogasto.co/"

    assert_response :success
    assert_match '<html lang="es">', response.body
    assert_match "<title>Controla tus finanzas personales | Yogasto</title>", response.body
    assert_match 'name="description"', response.body
    assert_match 'rel="canonical" href="https://yogasto.co/"', response.body
    assert_match 'name="robots" content="index,follow"', response.body
    assert_match 'property="og:title"', response.body
    assert_match 'name="twitter:card"', response.body
  end

  test "GET / redirects signed-in users to the dashboard (historical behavior)" do
    user = User.create!(name: "CMS User", email: "cms_home@example.com", password: "password123")
    sign_in user

    get "https://yogasto.co/"

    assert_redirected_to dashboard_path
  end

  test "publish workflow: draft changes are not publicly visible until published" do
    get "https://yogasto.co/"
    refute_match "Prototipo de borrador", response.body

    Maglev::I18n.with_locale("es") do
      page = Maglev::Page.by_path("index").first
      section = page.sections.find { |s| s["type"] == "hero" }
      setting = section["settings"].find { |s| s["id"] == "eyebrow" }
      setting["value"] = "Prototipo de borrador"
      page.save!
    end

    get "https://yogasto.co/"
    assert_response :success
    refute_match "Prototipo de borrador", response.body
  end

  test "unpublished CMS pages 404 for visitors" do
    add_maglev_page(title: "Contacto", path: "contacto")

    get "https://yogasto.co/contacto"

    assert_response :not_found
  end

  test "legacy /home alias redirects to the CMS home" do
    get "https://yogasto.co/home"

    assert_response :moved_permanently
  end
end
