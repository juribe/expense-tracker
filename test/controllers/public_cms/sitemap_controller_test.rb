# frozen_string_literal: true

require "test_helper"

class PublicCmsSitemapControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PublicCmsTestSupport

  setup do
    @site = create_maglev_site!
  end

  test "GET /sitemap.xml lists published pages with canonical URLs" do
    get "https://yogasto.co/sitemap.xml"

    assert_response :success
    assert_match %r{<urlset}, response.body
    assert_match "<loc>https://yogasto.co/</loc>", response.body
    assert_match "<loc>https://yogasto.co/contact</loc>", response.body
    assert_match %r{<lastmod>\d{4}-\d{2}-\d{2}</lastmod>}, response.body
  end

  test "GET /sitemap keeps the native entry point working with the published pages" do
    get "https://yogasto.co/sitemap"

    assert_response :success
    assert_match "<loc>https://yogasto.co/</loc>", response.body
  end

  test "never-published draft pages are not listed" do
    add_maglev_page(title: "Contacto", path: "contacto")

    get "https://yogasto.co/sitemap.xml"

    assert_response :success
    refute_match "contacto", response.body
  end

  test "invisible pages are not listed" do
    page = Maglev::Page.by_path("index").first
    page.update!(visible: false)

    get "https://yogasto.co/sitemap.xml"

    assert_response :success
    refute_match "<loc>https://yogasto.co/</loc>", response.body
    assert_match "<loc>https://yogasto.co/contact</loc>", response.body
  end
end
