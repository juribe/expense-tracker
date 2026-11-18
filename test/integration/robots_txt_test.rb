# frozen_string_literal: true

require "test_helper"

# The public robots.txt allows crawling and points crawlers to the sitemap.
class RobotsTxtTest < ActionDispatch::IntegrationTest
  test "allows every crawler and advertises the canonical sitemap" do
    get "/robots.txt"

    assert_response :success
    assert_match "User-agent: *", response.body
    assert_match "Allow: /", response.body
    assert_match "Sitemap: https://yogasto.co/sitemap", response.body
    refute_match "Disallow: /", response.body
  end
end
