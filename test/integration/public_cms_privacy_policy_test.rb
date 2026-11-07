# frozen_string_literal: true

require "test_helper"

# Public privacy policy rendered from the Maglev privacy_document section.
class PublicCmsPrivacyPolicyTest < ActionDispatch::IntegrationTest
  include PublicCmsTestSupport
  include PrivacyPolicyTestSupport

  setup do
    @site = create_maglev_site!
    LegalDocument::Seeder.new(site: @site, data: privacy_seed_data).call(force: true, publish: true)
  end

  test "la política se renderiza con hero, índice y doce secciones" do
    get "https://yogasto.co/privacidad"

    assert_response :success
    assert_match "<title>Política de privacidad | Yogasto</title>", response.body
    assert_select "h1", count: 1
    assert_select "section.privacy-hero", 1
    assert_select "[data-privacy-toc] a", count: 12
    assert_select "[data-privacy-section]", count: 12
    assert_select "#responsable", 1
    assert_select "#datos .privacy-card", count: 6
    assert_select "#terceros .privacy-provider", count: 6
    assert_select ".privacy-cta a[href='/contactanos']", 1
    assert_select "footer.site-footer a[href='/privacidad']", minimum: 1
  end

  test "el índice se genera desde las secciones y marca la primera como activa" do
    get "https://yogasto.co/privacidad"

    assert_select "[data-privacy-toc] a[aria-current='true']", count: 1, text: "Responsable"
    assert_select "[data-privacy-toc] a[href='#ia']", 1
  end

  test "los proveedores confirmados se muestran en la sección de terceros" do
    get "https://yogasto.co/privacidad"

    assert_match "ePayco", response.body
    assert_match "Mistral", response.body
    assert_match "Google / Gmail", response.body
  end

  test "la página mantiene metadatos SEO y noindex mientras está en revisión" do
    get "https://yogasto.co/privacidad"

    assert_select "meta[name='robots'][content='noindex,follow']", 1
    assert_select "link[rel='canonical'][href='https://yogasto.co/privacidad']", 1
    assert_select "meta[property='og:title']", 1
  end

  test "la página noindex no entra al sitemap mientras está en revisión" do
    get "https://yogasto.co/sitemap.xml"

    assert_response :success
    refute_match "<loc>https://yogasto.co/privacidad</loc>", response.body
  end

  test "/privacy redirige a /privacidad" do
    get "https://yogasto.co/privacy"

    assert_response :moved_permanently
    assert_redirected_to "/privacidad"
  end
end
