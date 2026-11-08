require "test_helper"
class ReportsCssTest < ActionDispatch::IntegrationTest
  test "reports stylesheet is linked and served" do
    user = User.create!(name: "Css User", email: "reports_css_test@example.com", password: "password123")
    sign_in_as user
    get reports_overview_path
    assert_response :success
    assert_match %r{/assets/reports}, response.body
    css_path = response.body.match(%r{(/assets/reports[^"]+\.css)})[1]
    get css_path
    assert_response :success
    assert_match "filters-card", response.body
    filters_grid = response.body[/\.filters-grid\s*\{[^}]*\}/]
    assert_match(/grid-template-columns:\s*repeat\(2,/, filters_grid)
    assert_match(/\.report-transactions-modal\s*\{[^}]*--bs-modal-width:\s*900px/, response.body)
  end
end
