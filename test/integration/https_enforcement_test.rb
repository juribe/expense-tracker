# frozen_string_literal: true

require "test_helper"

# Production relies on the edge (Cloudflare/Tunnel) forwarding
# X-Forwarded-Proto: https. assume_ssl would fabricate that fact before
# ActionDispatch::SSL runs and make the plaintext redirect unreachable.
class HttpsEnforcementTest < ActiveSupport::TestCase
  def app
    ->(_env) { [ 200, { "content-type" => "text/plain" }, [ "ok" ] ] }
  end

  test "plain http is redirected when ssl is not assumed" do
    status, headers, = ActionDispatch::SSL.new(app, redirect: {}).call(
      Rack::MockRequest.env_for("http://example.org/")
    )

    assert_includes [ 301, 307, 308 ], status
    assert_match %r{\Ahttps://example\.org/}, headers["location"]
  end

  test "https passes through" do
    status, = ActionDispatch::SSL.new(app, redirect: {}).call(
      Rack::MockRequest.env_for("https://example.org/")
    )

    assert_equal 200, status
  end

  test "production does not assume ssl and keeps force_ssl" do
    source = Rails.root.join("config/environments/production.rb").read

    refute_match(/^\s*config\.assume_ssl\s*=\s*true/, source)
    assert_match(/^\s*config\.force_ssl\s*=\s*true/, source)
  end
end
