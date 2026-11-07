# frozen_string_literal: true

require "test_helper"

class ReportsPagesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "Reports Pages", email: "reports_pages_test@example.com", password: "password123")
    @category = Category.create!(name: "Alimentación", is_default: true, category_type: "expense")
    @bank = @user.money_sources.create!(name: "Davibank", kind: "account", active: true, starting_balance: 1_000_000_000)
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

  test "report period select submits through data-auto-submit, not inline handlers" do
    get reports_overview_path

    assert_select "select[data-auto-submit]"
    assert_not response.body.include?("onchange=\"this.form.submit()\"")
  end

  test "GET /reports/by_category renders" do
    get reports_by_category_path
    assert_response :success
  end

  test "GET /reports/trends renders" do
    get reports_trends_path
    assert_response :success
  end

  test "reports charts format money values with whole pesos" do
    @user.expenses.create!(amount: -1_234_567, date: Date.current, category: @category, money_source: @bank, description: "x")

    get reports_by_category_path
    assert_response :success
    assert_includes response.body, '"prefix":"$"'
    assert_includes response.body, '"thousands":"."'
    assert_includes response.body, '"decimal":","'
    assert_includes response.body, '"round":0'

    get reports_trends_path
    assert_response :success
    assert_includes response.body, '"prefix":"$"'
    assert_includes response.body, '"round":0'
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

  test "GET /reports/insights explains when there is not enough history" do
    @user.expenses.create!(amount: -100_000, date: Date.current, category: @category, money_source: @bank, description: "only current")

    get reports_insights_path

    assert_response :success
    assert_select "[data-testid=insights-insufficient-data]", text: /Falta información/
    assert_select "[data-testid=insight]", count: 0
  end

  test "reports pages include the chip click-through script" do
    get reports_by_category_path
    assert_response :success
    scripts = Nokogiri::HTML(response.body).css("script[src]").map { |s| s["src"] }
    assert scripts.any? { |src| src.include?("reports") && src.end_with?(".js") || src.include?("reports-") }
  end

  test "GET /reports/available_cycle renders the report tools" do
    get reports_available_cycle_path
    assert_response :success
    assert_select "[data-testid=available-cycle]"
    assert_select "[data-available-cycle-search]"
    assert_select "button[data-available-cycle-sort=due_date]"
    assert_select "button[data-available-cycle-sort=missing]"
    assert_select "[data-available-cycle-mode=values]"
    assert_select "[data-available-cycle-mode=percent]"
  end

  test "GET /reports/available_cycle renders pending expense rows with due metadata" do
    @user.recurring_templates.create!(category: @category, kind: "expense", amount: 100_000,
                                      frequency: "monthly", payment_day: 28, active: true,
                                      description: "Internet", money_source: @bank)

    get reports_available_cycle_path

    assert_response :success
    assert_select "[data-available-cycle-row]", 1
    assert_select "tr[data-available-cycle-row][data-missing]"
    assert_select ".available-expense-name", text: "Internet"
    assert_select ".available-missing"
    assert_select ".available-due-tag"
    assert_select ".available-row-action-link", 0
  end

  test "GET /reports/available_cycle renders a single cycle summary bar" do
    get reports_available_cycle_path

    assert_response :success
    assert_select ".available-summary-bar .available-summary-base"
    assert_select ".available-summary-bar .available-summary-due"
    assert_select ".available-summary-bar .available-summary-left"
    assert_select ".available-summary-current-track", 0
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

  test "GET /reports renders only the period picker, not the filters card" do
    @user.update!(financial_cycle_start_day: 20)

    get reports_overview_path

    assert_response :success
    assert_select "#report-period-select"
    assert_select "#report-period-select option[value=this_cycle]"
    assert_select "form .filters-card", count: 0
    assert_select "select[name=category_id]", count: 0
    assert_select "select[name=money_source_id]", count: 0
    assert_select "select[name=kind]", count: 0
  end

  test "GET /reports scopes the summary to the selected financial cycle" do
    @user.update!(financial_cycle_start_day: 20)
    cycle = PayCycle.current(@user)

    @user.expenses.create!(amount: -100_000, date: cycle.starts + 1.day,
                           category: @category, money_source: @bank, description: "inside cycle")
    @user.expenses.create!(amount: -999_999, date: cycle.starts - 1.day,
                           category: @category, money_source: @bank, description: "outside cycle")

    get reports_overview_path(period: "this_cycle")

    assert_response :success
    assert_select "[data-testid=expenses-total]", text: "$100.000"
  end

  test "GET /reports uses the current financial cycle by default" do
    travel_to Date.new(2026, 11, 7) do
      @user.update!(financial_cycle_start_day: 20)
      cycle = PayCycle.current(@user)

      @user.expenses.create!(amount: -100_000, date: cycle.starts + 1.day,
                             category: @category, money_source: @bank, description: "inside cycle")
      @user.expenses.create!(amount: -999_999, date: cycle.starts - 1.day,
                             category: @category, money_source: @bank, description: "outside cycle")

      get reports_overview_path

      assert_response :success
      assert_select "[data-testid=expenses-total]", text: "$100.000"
      assert_select "#report-period-select option[value=this_cycle][selected]"
    end
  end

  test "sidebar includes the reports link" do
    get reports_overview_path
    assert_select "a[href='#{reports_overview_path}']"
  end
end
