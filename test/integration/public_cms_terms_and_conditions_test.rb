# frozen_string_literal: true

require "test_helper"

# Public terms and conditions rendered from the shared Maglev legal document.
class PublicCmsTermsAndConditionsTest < ActionDispatch::IntegrationTest
  include PublicCmsTestSupport
  include PrivacyPolicyTestSupport

  setup do
    @site = create_maglev_site!
    LegalDocument::Seeder.new(site: @site, data: terms_seed_data).call(force: true, publish: true)
  end

  test "la página se renderiza con hero, breadcrumb e índice de 14 secciones" do
    get "https://yogasto.co/terminos-y-condiciones"

    assert_response :success
    assert_match "<title>Términos y condiciones | Yogasto</title>", response.body
    assert_select "h1", count: 1
    assert_select "section.privacy-hero", 1
    assert_select ".privacy-crumb", text: /Información legal/
    assert_select "[data-privacy-toc] a", count: 14
    assert_select "[data-privacy-section]", count: 14
    assert_select "#aceptacion", 1
    assert_select "#planes", 1
    assert_select "#pagos", 1
    assert_select "#ley", 1
    assert_select ".privacy-cta a[href='/ayuda']", 1
    assert_select "footer.site-footer a[href='/terminos-y-condiciones']", minimum: 1
  end

  test "las secciones numeradas y el estado activo se generan desde Maglev" do
    get "https://yogasto.co/terminos-y-condiciones"

    assert_select "[data-privacy-toc] a[aria-current='true']", count: 1, text: /Aceptación de los términos/
    assert_select "[data-privacy-section] h2 .privacy-section__number", count: 14
    assert_select "[data-privacy-toc-link='ia']", 1
  end

  test "planes y pagos describen las condiciones reales sin renovación automática" do
    get "https://yogasto.co/terminos-y-condiciones"

    assert_match "La renovación no es automática por defecto", response.body
    assert_match "tarjeta y PSE", response.body
    assert_match "ePayco", response.body
    assert_match "/privacidad", response.body
  end

  test "la página mantiene noindex y canonical durante la revisión legal" do
    get "https://yogasto.co/terminos-y-condiciones"

    assert_select "meta[name='robots'][content='noindex,follow']", 1
    assert_select "link[rel='canonical'][href='https://yogasto.co/terminos-y-condiciones']", 1
    assert_select "meta[property='og:title']", 1
  end

  test "la página noindex no entra al sitemap" do
    get "https://yogasto.co/sitemap.xml"

    assert_response :success
    refute_match "<loc>https://yogasto.co/terminos-y-condiciones</loc>", response.body
  end

  test "/terms redirige a /terminos-y-condiciones" do
    get "https://yogasto.co/terms"

    assert_response :moved_permanently
    assert_redirected_to "/terminos-y-condiciones"
  end
end
