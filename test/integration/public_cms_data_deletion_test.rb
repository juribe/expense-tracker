# frozen_string_literal: true

require "test_helper"

# Public data deletion page rendered from the shared Maglev legal document.
class PublicCmsDataDeletionTest < ActionDispatch::IntegrationTest
  include PublicCmsTestSupport
  include PrivacyPolicyTestSupport

  setup do
    @site = create_maglev_site!
    LegalDocument::Seeder.new(site: @site, data: data_deletion_seed_data).call(force: true, publish: true)
  end

  test "la página se renderiza con hero, índice y siete secciones" do
    get "https://yogasto.co/eliminacion-de-datos"

    assert_response :success
    assert_match "<title>Eliminación de datos | Yogasto</title>", response.body
    assert_select "h1", count: 1
    assert_select "section.privacy-hero", 1
    assert_select "[data-privacy-toc] a", count: 7
    assert_select "[data-privacy-section]", count: 7
    assert_select "#perfil", 1
    assert_select "#solicitud", 1
  end

  test "explica cómo eliminar la cuenta desde el perfil" do
    get "https://yogasto.co/eliminacion-de-datos"

    assert_select "#perfil li", count: 4
    assert_match "Mi perfil", response.body
    assert_match "ELIMINAR", response.body
    assert_match "Cancelar mi cuenta", response.body
    assert_match "permanente", response.body
  end

  test "explica la eliminación sin acceso a la cuenta y los datos de WhatsApp" do
    get "https://yogasto.co/eliminacion-de-datos"

    assert_select "#whatsapp", text: /WhatsApp/
    assert_select "#solicitud", text: /hola@yogasto\.co/
    assert_select "#solicitud li", count: 3
    assert_match "Ley 1581 de 2012", response.body
    assert_match "Nunca te pediremos tu contraseña", response.body
  end

  test "mantiene metadatos SEO y entra al sitemap" do
    get "https://yogasto.co/eliminacion-de-datos"

    assert_select "meta[name='robots'][content='index,follow']", 1
    assert_select "link[rel='canonical'][href='https://yogasto.co/eliminacion-de-datos']", 1
    assert_select "meta[property='og:title']", 1

    get "https://yogasto.co/sitemap.xml"

    assert_response :success
    assert_match "<loc>https://yogasto.co/eliminacion-de-datos</loc>", response.body
  end

  test "carga los estilos y scripts del documento legal" do
    get "https://yogasto.co/eliminacion-de-datos"

    assert_select "link[rel='stylesheet'][href*='privacy']", minimum: 1
    assert_select "script[src*='privacy']", minimum: 1
  end

  test "el footer del sitio enlaza la página" do
    get "https://yogasto.co/eliminacion-de-datos"

    assert_select "footer.site-footer a[href='/eliminacion-de-datos']", minimum: 1
  end
end
