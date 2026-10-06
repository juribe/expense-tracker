# frozen_string_literal: true

require "test_helper"

class ReportsPagesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "Reports Pages", email: "reports_pages_test@example.com", password: "password123")
    @category = Category.create!(name: "Alimentación", is_default: true, category_type: "expense")
    @bank = @user.money_sources.create!(name: "Davibank", kind: "account", active: true)
    sign_in @user
  end

  test "GET /reports renders overview with cards" do
    @user.expenses.create!(amount: -100_000, date: Date.current, category: @category, money_source: @bank, description: "x")

    get reports_overview_path
    assert_response :success
    assert_select "h1", text: /Informes/
    assert_select "[data-testid=overview-cards]"
    assert_select "[data-testid=income-total]"
  end

  test "GET /reports redirects unauthenticated user" do
    sign_out @user

    get reports_overview_path
    assert_response :redirect
    assert_match(/sign_in/, response.location)
  end

  test "GET /reports/by_category renders" do
    get reports_by_category_path
    assert_response :success
  end

  test "GET /reports/trends renders" do
    get reports_trends_path
    assert_response :success
  end

  test "GET /reports/budgets renders" do
    get reports_budgets_path
    assert_response :success
  end

  test "GET /reports/credit_cards renders" do
    get reports_credit_cards_path
    assert_response :success
  end

  test "GET /reports/loans renders" do
    get reports_loans_path
    assert_response :success
  end

  test "GET /reports/recurring renders" do
    get reports_recurring_path
    assert_response :success
  end

  test "GET /reports/money_sources renders" do
    get reports_money_sources_path
    assert_response :success
  end

  test "GET /reports/transfers renders" do
    get reports_transfers_path
    assert_response :success
  end

  test "GET /reports/insights renders" do
    get reports_insights_path
    assert_response :success
  end

  test "reports pages include the chip click-through script" do
    get reports_by_category_path
    assert_response :success
    scripts = Nokogiri::HTML(response.body).css("script[src]").map { |s| s["src"] }
    assert scripts.any? { |src| src.include?("reports") && src.end_with?(".js") || src.include?("reports-") }
  end

  test "GET /reports/transactions renders drill-down with filters" do
    @user.expenses.create!(amount: -100_000, date: Date.current, category: @category, money_source: @bank, description: "coffee")

    get reports_transactions_path(period: "this_month", category_id: @category.id)
    assert_response :success
    assert_select "table"
  end

  test "GET /reports with custom range" do
    get reports_overview_path(period: "custom", start_date: 1.month.ago.to_date, end_date: Date.current)
    assert_response :success
  end

  test "sidebar includes the reports link" do
    get reports_overview_path
    assert_select "a[href='#{reports_overview_path}']"
  end
end
