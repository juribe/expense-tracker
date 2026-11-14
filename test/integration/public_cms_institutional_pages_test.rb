# frozen_string_literal: true

require "test_helper"

# Institutional pages referenced by the shared footer and by the Contáctanos
# links. The full security page has its own public CMS test.
class PublicCmsInstitutionalPagesTest < ActionDispatch::IntegrationTest
  include PublicCmsTestSupport

  setup do
    create_maglev_site!
  end

  test "el Centro de ayuda se publica como landing de ayuda" do
    get "https://yogasto.co/ayuda"

    assert_response :success
    assert_match "<title>Centro de ayuda | Yogasto</title>", response.body
    assert_select "h1", count: 1
    assert_select "section.help-hero", 1
    assert_select "section.help-categories", 1
    assert_select "section.institutional-content", 1
  end

  test "las páginas institucionales y el Centro de ayuda existen en Maglev" do
    %w[ayuda privacidad terminos-y-condiciones seguridad eliminacion-de-datos].each do |path|
      assert_not_nil Maglev::Page.by_path(path).first, "Falta la página Maglev #{path}"
    end
  end

  test "el footer compartido conserva los enlaces institucionales" do
    get "https://yogasto.co/contact"

    %w[/contact /ayuda /privacidad /terminos-y-condiciones /seguridad /eliminacion-de-datos].each do |href|
      assert_select "footer.site-footer a[href='#{href}']", minimum: 1
    end
  end

  test "/help redirige al nuevo Centro de ayuda" do
    get "https://yogasto.co/help"

    assert_response :moved_permanently
    assert_redirected_to "/ayuda"
  end
end
