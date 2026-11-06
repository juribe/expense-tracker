# frozen_string_literal: true

require "test_helper"

# Minimal institutional pages referenced by the shared footer and by the
# Contáctanos links. They are Maglev pages with provisional, reviewable copy.
class PublicCmsInstitutionalPagesTest < ActionDispatch::IntegrationTest
  include PublicCmsTestSupport

  INSTITUTIONAL_PAGES = {
    "/help" => "Centro de ayuda",
    "/privacy" => "Política de privacidad",
    "/security" => "Seguridad",
    "/terms" => "Términos y condiciones"
  }.freeze

  setup do
    create_maglev_site!
  end

  test "las páginas institucionales mínimas se publican y responden" do
    INSTITUTIONAL_PAGES.each do |path, title|
      get "https://yogasto.co#{path}"

      assert_response :success, "#{path} debe estar publicada"
      assert_match "<title>#{title} | Yogasto</title>", response.body
      assert_select "h1", count: 1
      assert_match title, response.body
      assert_select "section.institutional-hero", 1
      assert_select "section.institutional-content", 1
    end
  end

  test "las páginas institucionales existen en Maglev" do
    %w[help privacy security terms].each do |path|
      assert_not_nil Maglev::Page.by_path(path).first, "Falta la página Maglev #{path}"
    end
  end

  test "el footer compartido conserva los enlaces institucionales" do
    get "https://yogasto.co/contact"

    %w[/contact /help /privacy /terms /security].each do |href|
      assert_select "footer.site-footer a[href='#{href}']", minimum: 1
    end
  end
end
