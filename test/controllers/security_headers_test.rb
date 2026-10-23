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
end
