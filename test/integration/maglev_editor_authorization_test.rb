# frozen_string_literal: true

require "test_helper"

# The Maglev editor is protected by the host app authentication: only users
# flagged as admin may open it. Anonymous users are sent to the sign-in screen
# and regular users back to the app root.
class MaglevEditorAuthorizationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PublicCmsTestSupport

  setup do
    @site = create_maglev_site!
  end

  test "anonymous users are redirected to the sign-in screen" do
    get "https://yogasto.co/maglev/editor"

    assert_response :redirect
    assert_equal "/users/sign_in", URI.parse(response.location).path
  end

  test "regular users cannot open the editor" do
    user = User.create!(name: "Editor Wannabe", email: "editor_wannabe@example.com", password: "password123")
    sign_in user

    get "https://yogasto.co/maglev/editor"

    assert_response :redirect
    assert_equal "/", URI.parse(response.location).path
  end

  test "admins can open the editor and land on the home page editor" do
    admin = User.create!(name: "CMS Admin", email: "cms_admin@example.com", password: "password123", admin: true)
    sign_in admin

    get "https://yogasto.co/maglev/editor"

    assert_response :redirect
    assert_match %r{^/maglev/editor/es/[a-f0-9-]+$}, URI.parse(response.location).path
  end

  test "admins can persist page SEO edits through the editor" do
    admin = User.create!(name: "SEO Admin", email: "seo_admin@example.com", password: "password123", admin: true)
    sign_in admin

    page = Maglev::Page.by_path("index").first

    put("https://yogasto.co/maglev/editor/es/#{@site.id}/pages/#{page.id}",
        params: { page: { title: "Home", visible: true, seo_title: "SEO nuevo", canonical_url: "https://yogasto.co/" } },
        headers: { "accept" => "text/vnd.turbo-stream.html" })

    page.reload
    Maglev::I18n.with_locale("es") do
      assert_equal "SEO nuevo", page.seo_title
      assert_equal "https://yogasto.co/", page.canonical_url
    end
  end
end
