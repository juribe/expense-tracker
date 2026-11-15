# frozen_string_literal: true

require "test_helper"

# The app is installable as a PWA: a public manifest, a root-scoped service
# worker that never caches authenticated responses, and install/update entry
# points in the signed-in shell.
class PwaTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PublicCmsTestSupport

  setup do
    @user = User.create!(
      email: "pwa-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current,
      financial_cycle_start_day: 1,
      debt_capacity_target_percentage: 50,
      debt_capacity_alert_percentage: 80
    )
  end

  test "manifest is public and describes a standalone installable app" do
    get pwa_manifest_path

    assert_response :success
    assert_includes response.media_type, "manifest"

    manifest = JSON.parse(response.body)

    assert_equal "Yogasto", manifest["name"]
    assert_equal "Yogasto", manifest["short_name"]
    assert_equal "/", manifest["start_url"]
    assert_equal "/", manifest["scope"]
    assert_equal "standalone", manifest["display"]
    assert_equal "portrait", manifest["orientation"]
    assert_match(/\A#[0-9a-f]{6}\z/i, manifest["theme_color"])
    assert_match(/\A#[0-9a-f]{6}\z/i, manifest["background_color"])
  end

  test "manifest declares 192 and 512 icons, including maskable versions" do
    get pwa_manifest_path
    icons = JSON.parse(response.body).fetch("icons")

    any_icons = icons.select { |icon| icon["purpose"] == "any" }
    maskable_icons = icons.select { |icon| icon["purpose"] == "maskable" }

    assert_equal %w[192x192 512x512], any_icons.map { |icon| icon["sizes"] }.sort
    assert_equal %w[192x192 512x512], maskable_icons.map { |icon| icon["sizes"] }.sort
    assert(icons.all? { |icon| icon["type"] == "image/png" })
  end

  test "manifest icons point to png files with the declared dimensions" do
    get pwa_manifest_path

    JSON.parse(response.body).fetch("icons").each do |icon|
      path = Rails.root.join("public#{icon.fetch("src")}")
      assert File.exist?(path), "Missing manifest icon #{path}"

      width, height = File.binread(path, 24)[16, 8].unpack("N2")
      assert_equal icon.fetch("sizes"), "#{width}x#{height}"
    end
  end

  test "service worker is public, root scoped and prepared for offline shell only" do
    get pwa_service_worker_path

    assert_response :success
    assert_includes response.media_type, "javascript"
    assert_equal "no-cache", response.headers["Cache-Control"]
    assert_equal "/", response.headers["Service-Worker-Allowed"]

    %w[install activate fetch message SKIP_WAITING].each do |token|
      assert_includes response.body, token
    end

    assert_includes response.body, "/offline.html"
    assert_not_includes response.body, "/dashboard"
    assert_not_includes response.body, "/expenses"
  end

  test "signed out landing page links the manifest and apple metadata" do
    create_maglev_site!

    get "https://yogasto.co/"

    assert_response :success
    assert_select "link[rel='manifest'][href='#{pwa_manifest_path}']"
    assert_select "link[rel='apple-touch-icon']"
    assert_select "meta[name='apple-mobile-web-app-title'][content='Yogasto']"
    assert_select "meta[name='viewport'][content*='viewport-fit=cover']"
  end

  test "signed in shell exposes install and update entry points" do
    sign_in @user

    get dashboard_path

    assert_response :success
    assert_select "[data-pwa-install-menu]", count: 1
    assert_select "[data-pwa-install-trigger]", minimum: 1
    assert_select "[data-pwa-install-banner]", count: 1
    assert_select "[data-pwa-update]", count: 1
    assert_select "script[src*='pwa']", minimum: 1
  end

  test "profile page offers the install shortcut as settings entry point" do
    sign_in @user

    get profile_path

    assert_response :success
    assert_select "[data-pwa-install-settings]", count: 1
  end
end
