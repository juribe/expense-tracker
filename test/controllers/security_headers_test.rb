# frozen_string_literal: true

require "test_helper"

# Security headers: the CSP must ship on every response (percentages, SPA).
class SecurityHeadersTest < ActionDispatch::IntegrationTest
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

    script_directive = response.headers["Content-Security-Policy"].split(";")
                                                        .find { |d| d.strip.start_with?("script-src") }
    assert_not_nil script_directive
    assert_includes script_directive, "'self'"
    assert_includes script_directive, "cdn.jsdelivr.net"
    assert_not_includes script_directive, "unsafe-inline"
  end

  test "style-src stays conservative while inline styles remain in views" do
    get root_path

    style_directive = response.headers["Content-Security-Policy"].split(";")
                                                        .find { |d| d.strip.start_with?("style-src") }
    assert_not_nil style_directive
    assert_includes style_directive, "'self'"
    assert_includes style_directive, "fonts.googleapis.com"
    assert_includes style_directive, "unsafe-inline"
  end
end
