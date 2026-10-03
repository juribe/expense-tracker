# frozen_string_literal: true
require "test_helper"
class ChartkickAssetTest < ActionDispatch::IntegrationTest
  test "chartkick and Chart.bundle assets resolve" do
    user = User.create!(name: "Asset User", email: "chartkick_asset_test@example.com", password: "password123")
    sign_in_as(user)
    get reports_trends_path
    assert_response :success
    scripts = Nokogiri::HTML(response.body).css("script[src]").map { |s| s["src"] }
    chartkick = scripts.find { |s| s.include?("chartkick") }
    chartjs = scripts.find { |s| s.include?("Chart.bundle") }
    assert chartkick, "chartkick script missing"
    assert chartjs, "Chart.bundle script missing"
    get chartkick
    assert_response :success
    get chartjs
    assert_response :success
  end
end
