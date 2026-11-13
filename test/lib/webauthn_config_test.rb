# frozen_string_literal: true

require "test_helper"

class WebauthnConfigTest < ActiveSupport::TestCase
  test "accepts the origin host or a parent domain" do
    assert WebauthnConfig.valid_rp_id?(host: "app.example.com", rp_id: "app.example.com")
    assert WebauthnConfig.valid_rp_id?(host: "app.example.com", rp_id: "example.com")
  end

  test "rejects an unrelated domain, a wildcard or a blank value" do
    refute WebauthnConfig.valid_rp_id?(host: "app.example.com", rp_id: "other.com")
    refute WebauthnConfig.valid_rp_id?(host: "app.example.com", rp_id: "ample.com")
    refute WebauthnConfig.valid_rp_id?(host: "app.example.com", rp_id: "*.example.com")
    refute WebauthnConfig.valid_rp_id?(host: "app.example.com", rp_id: "")
  end
end
