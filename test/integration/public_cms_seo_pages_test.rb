# frozen_string_literal: true

require "test_helper"

# Renders the commercial landing pages and the refreshed help articles created
# by CmsPage::SeoContentSeeder, including metadata, JSON-LD and internal links.
class PublicCmsSeoPagesTest < ActionDispatch::IntegrationTest
  include SeoContentTestSupport

  setup do
    prepare_seo_site!
    run_seo_seeder!
  end

  test "each commercial landing page renders a single H1 and unique metadata" do
    titles = []
    descriptions = []

    SeoContentSeed::LANDING_PAGES.each do |attributes|
      get "https://yogasto.co/#{attributes[:path]}"

      assert_response :success
      assert_select "h1", count: 1
      assert_select "h1", text: attributes[:h1]
      assert_match "<title>#{ERB::Util.html_escape(attributes[:seo_title])} | Yogasto</title>", response.body
      assert_match 'name="description"', response.body
      assert_match "https://yogasto.co/#{attributes[:path]}", response.body
      assert_match 'name="robots" content="index,follow"', response.body

      titles << attributes[:seo_title]
      descriptions << attributes[:meta_description]
    end

    assert_equal titles.size, titles.uniq.size
    assert_equal descriptions.size, descriptions.uniq.size
  end

  test "landing pages expose factual SoftwareApplication structured data" do
    get "https://yogasto.co/funciones/registrar-gastos-por-whatsapp"

    assert_response :success
    json_ld = json_ld_payloads(response.body)
    types = json_ld.map { |entry| entry["@type"] }

    assert_equal 1, types.count("Organization")
    assert_equal 1, types.count("WebSite")
    assert_equal 1, types.count("SoftwareApplication")
    assert_equal 1, types.count("BreadcrumbList")
    refute_includes types, "FAQPage"

    application = json_ld.find { |entry| entry["@type"] == "SoftwareApplication" }
    assert_equal "Yogasto", application["name"]
    assert_equal "FinanceApplication", application["applicationCategory"]
    assert_equal "Web", application["operatingSystem"]
    offers = Array(application["offers"])
    assert offers.any?
    offers.each do |offer|
      assert_equal "COP", offer["priceCurrency"]
      assert offer["price"].present?
      refute_match(/renew/i, offer["name"].to_s)
    end
  end

  test "refreshed help articles keep their URLs and link to the landing pages" do
    get "https://yogasto.co/ayuda/herramientas-inteligentes/registrar-gastos-por-whatsapp"

    assert_response :success
    assert_select "h1", count: 1
    assert_match "<title>Registrar gastos por WhatsApp con IA | Yogasto</title>", response.body
    assert_select "a[href='/funciones/registrar-gastos-por-whatsapp']", minimum: 1
    assert_select "a[href='/precios']", minimum: 1
    assert_match "Pagué 35.000 en gasolina", response.body
    assert_match "Article", response.body
    assert_match "BreadcrumbList", response.body
  end

  test "help articles are linked from the landing pages" do
    get "https://yogasto.co/funciones/importar-gastos-desde-gmail"

    assert_response :success
    assert_select "a[href='/ayuda/herramientas-inteligentes/conectar-gmail']", minimum: 1
    assert_select "a[href='/precios']", minimum: 1
    assert_select "a[href='/users/sign_up']", minimum: 1
  end

  test "the refreshed WhatsApp article documents examples and privacy" do
    get "https://yogasto.co/ayuda/herramientas-inteligentes/registrar-gastos-por-whatsapp"

    assert_response :success
    assert_match "Pagué 35.000 en gasolina", response.body
    assert_match "Almorcé por 28.000", response.body
    assert_match "Compré mercado por 150.000", response.body
    assert_match(/no lee tus conversaciones personales/i, response.body)
  end

  test "the refreshed Gmail article states the verified retention behavior" do
    get "https://yogasto.co/ayuda/herramientas-inteligentes/conectar-gmail"

    assert_response :success
    assert_match(/no guarda el cuerpo completo de tus correos/i, response.body)
    assert_match(/cómo desconectar Gmail/i, response.body)
    assert_select "a[href='/funciones/importar-gastos-desde-gmail']", minimum: 1
  end

  test "the Día de Balance article no longer claims to be a Pro feature" do
    get "https://yogasto.co/ayuda/cuentas-y-medios-de-dinero/dia-de-balance"

    assert_response :success
    assert_select "h1", count: 1
    prose = css_select(".help-prose").text
    refute_match(/Herramienta Pro/i, prose)
    refute_match(/funciones Pro/i, prose)
    assert_match(/no requiere una membresía Pro/i, prose)
  end

  private

  def json_ld_payloads(body)
    body.scan(%r{<script type="application/ld\+json">(.*?)</script>}m).filter_map do |match|
      JSON.parse(CGI.unescapeHTML(match.first))
    rescue JSON::ParserError
      nil
    end
  end
end
