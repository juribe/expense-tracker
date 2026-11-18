# frozen_string_literal: true

require "test_helper"

class CmsPageSeoContentSeederTest < ActiveSupport::TestCase
  include SeoContentTestSupport

  setup { prepare_seo_site! }

  test "updates the five help articles without changing their URLs" do
    paths = SeoContentSeed::ARTICLES.map { |article| article[:path] }

    run_seo_seeder!

    paths.each do |path|
      page = page_at(path)
      assert_not_nil page, "expected #{path} to exist"
      assert page.published?, "expected #{path} to remain published"
      assert page.visible?, "expected #{path} to remain visible"
      assert_equal "index,follow", page.meta_robots
      assert_match "https://yogasto.co/#{path}", page.canonical_url
    end
  end

  test "refreshes the editorial content of the WhatsApp article" do
    run_seo_seeder!

    page = page_at("ayuda/herramientas-inteligentes/registrar-gastos-por-whatsapp")
    text = page_text(page)

    assert_match "Pagué 35.000 en gasolina", text
    assert_match "solo procesa los mensajes que tú decides enviar", text
    assert_match "/funciones/registrar-gastos-por-whatsapp", text
  end

  test "refreshes the Gmail article with the verified retention statement" do
    run_seo_seeder!

    page = page_at("ayuda/herramientas-inteligentes/conectar-gmail")
    text = page_text(page)

    assert_match(/no guarda el cuerpo completo de tus correos/i, text)
    assert_match(/cómo desconectar Gmail/i, text)
    assert_match "/funciones/importar-gastos-desde-gmail", text
  end

  test "does not republish unchanged content" do
    run_seo_seeder!

    article = page_at("ayuda/primeros-pasos/que-es-yogasto")
    landing = page_at("funciones/app-para-controlar-gastos")
    home = page_at("index")
    published = [ article.published_at, landing.published_at, home.published_at ]

    travel_to 1.minute.from_now do
      run_seo_seeder!
    end

    assert_equal published,
                 [ page_at("ayuda/primeros-pasos/que-es-yogasto").published_at,
                   page_at("funciones/app-para-controlar-gastos").published_at,
                   page_at("index").published_at ]
  end

  test "removes the outdated Pro claim from the Día de Balance article" do
    run_seo_seeder!

    page = page_at("ayuda/cuentas-y-medios-de-dinero/dia-de-balance")
    text = page_text(page)

    refute_match(/funciones Pro/i, text)
    refute_match(/Herramienta Pro/i, text)
    assert_match(/no requiere una membresía Pro/i, text)
    assert_equal "index,follow", page.meta_robots
    assert_match "https://yogasto.co/ayuda/cuentas-y-medios-de-dinero/dia-de-balance", page.canonical_url
  end

  test "creates and publishes the five commercial landing pages" do
    assert_difference -> { Maglev::Page.count }, SeoContentSeed::LANDING_PAGES.size do
      run_seo_seeder!
    end

    SeoContentSeed::LANDING_PAGES.each do |attributes|
      page = page_at(attributes[:path])
      assert_not_nil page, "expected #{attributes[:path]} to exist"
      assert page.published?, "expected #{attributes[:path]} to be published"
      assert page.visible?, "expected #{attributes[:path]} to be visible"
      assert_equal attributes[:seo_title], page.seo_title
      assert_equal attributes[:meta_description], page.meta_description
      assert_equal attributes[:og_title], page.og_title
      assert_equal attributes[:og_description], page.og_description
      assert_equal "index,follow", page.meta_robots
      assert_equal "https://yogasto.co/#{attributes[:path]}", page.canonical_url
    end
  end

  test "is idempotent and keeps landing page URLs unique" do
    run_seo_seeder!

    assert_no_difference -> { Maglev::Page.count } do
      run_seo_seeder!
    end

    paths = SeoContentSeed::LANDING_PAGES.map { |attributes| attributes[:path] }
    assert_equal paths.size, paths.uniq.size
    paths.each do |path|
      assert_equal 1, Maglev::Page.by_path(path).count
    end
  end

  test "adds contextual links from the home page and the shared footer" do
    run_seo_seeder!

    home = page_at("index")
    home_sections = home.sections.select { |section| section["type"] == "link_cards" }
    assert_equal 1, home_sections.size, "expected exactly one link_cards section on the home page"
    home_links = Array(home_sections.first["blocks"]).map { |block| block_link_href(block) }
    assert_equal SeoContentSeed::LANDING_PAGES.size, home_links.size

    footer = Maglev::I18n.with_locale(@site.default_locale_prefix) { @site.find_section("footer") }
    footer_hrefs = Array(footer["blocks"]).map { |block| block_link_href(block) }
    SeoContentSeed::LANDING_PAGES.each do |attributes|
      assert_includes footer_hrefs, "/#{attributes[:path]}"
    end
  end

  test "keeps SEO titles and descriptions unique across published pages" do
    run_seo_seeder!

    pages = Maglev::I18n.with_locale(HelpCenter::LOCALE) do
      Maglev::Page.where(visible: true).where.not(published_at: nil).to_a
    end

    titles = pages.map { |page| page.seo_title.to_s.strip.downcase }
    descriptions = pages.map { |page| page.meta_description.to_s.strip.downcase }

    assert_equal titles.size, titles.uniq.size, "duplicate SEO titles: #{duplicate_values(titles).inspect}"
    assert_equal descriptions.size, descriptions.uniq.size,
                 "duplicate meta descriptions: #{duplicate_values(descriptions).inspect}"
    assert pages.none? { |page| page.seo_title.blank? || page.meta_description.blank? }
  end

  private

  def block_link_href(block)
    Array(block["settings"]).find { |setting| setting["id"] == "link" }
                            &.fetch("value", nil)
                            &.with_indifferent_access
                            &.fetch(:href, nil)
  end

  def duplicate_values(values)
    values.tally.select { |_value, count| count > 1 }.keys
  end
end
