# frozen_string_literal: true

require "test_helper"

# Security headers: the CSP must ship on every response (percentages, SPA).
class SecurityHeadersTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "responses carry the content security policy" do
    get root_path

    csp = response.headers["Content-Security-Policy"]
    assert_not_nil csp
    assert_includes csp, "default-src 'self'"
    assert_includes csp, "object-src 'none'"
    assert_includes csp, "frame-ancestors 'self'"
  end

  test "script-src forbids inline scripts" do
    get root_path

    script_directive = find_directive(response.headers["Content-Security-Policy"], "script-src")
    assert_not_nil script_directive
    assert_includes script_directive, "'self'"
    assert_includes script_directive, "cdn.jsdelivr.net"
    assert_not_includes script_directive, "unsafe-inline"
  end

  test "style-src is strict outside chart pages" do
    sign_in_user

    get transaction_rules_path
    assert_style_rejects_inline "transaction rules have no charts"

    style_directive = find_directive(response.headers["Content-Security-Policy"], "style-src")
    assert_not_nil style_directive
    assert_includes style_directive, "'self'"
    assert_includes style_directive, "fonts.googleapis.com"
    assert_not_includes style_directive, "unsafe-inline"
  end

  test "style-src allows Chartkick inline styles only on chart pages" do
    sign_in_user

    get dashboard_path
    assert_style_allows_inline "the dashboard renders server-generated charts"

    get reports_trends_path
    assert_style_allows_inline "the spending trend renders server-generated charts"
  end

  test "chart pages keep script-src strict" do
    sign_in_user

    get dashboard_path

    script_directive = find_directive(response.headers["Content-Security-Policy"], "script-src")
    assert_not_nil script_directive
    assert_not_includes script_directive, "unsafe-inline"
  end

  private

  def sign_in_user
    user = User.create!(name: "Csp User", email: "csp_headers@example.com", password: "password123")
    sign_in user
  end

  def find_directive(csp, name)
    csp.to_s.split(";").map(&:strip).find { |d| d.start_with?(name) }
  end

  def assert_style_allows_inline(reason)
    style_directive = find_directive(response.headers["Content-Security-Policy"], "style-src")
    assert_not_nil style_directive
    assert_includes style_directive, "'self'"
    assert_includes style_directive, "unsafe-inline", "#{reason} needs unrestricted inline styles"
  end

  def assert_style_rejects_inline(reason)
    style_directive = find_directive(response.headers["Content-Security-Policy"], "style-src")
    assert_not_nil style_directive
    assert_includes style_directive, "'self'"
    assert_includes style_directive, "fonts.googleapis.com"
    assert_not_includes style_directive, "unsafe-inline", "#{reason}"
  end
end
