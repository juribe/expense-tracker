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

  test "GET /reports renders the financial behavior chart and analysis" do
    income_category = Category.create!(name: "Salario", is_default: true, category_type: "income")
    @user.incomes.create!(amount: 10_000_000, date: Date.current, category: income_category,
                          money_source: @bank, description: "salary")
    @user.expenses.create!(amount: -2_000_000, date: Date.current, category: @category,
                           money_source: @bank, description: "x")

    get reports_overview_path

    assert_response :success
    assert_select "[data-testid=cash-flow-chart]"
    assert_select "[data-testid=financial-analysis]"
    assert_select "[data-testid=savings-rate]"
    assert_select "[data-testid=expense-share-note]", text: /de tus ingresos/
    assert_select "[data-testid=category-preview] .report-category-row", minimum: 1
    assert_select "[data-testid=overview-secondary] .report-secondary-card", count: 4
    assert_includes response.body, '"prefix":"$"'
    assert_includes response.body, "Ingresos"
    assert_includes response.body, "Gastos"
    assert_not_includes response.body, "translation_missing"
  end

  test "GET /reports renders compact empty states without movements" do
    get reports_overview_path

    assert_response :success
    assert_select "[data-testid=cash-flow-empty]"
    assert_select "[data-testid=financial-analysis-empty]"
    assert_select "[data-testid=savings-rate]", count: 0
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

  test "GET /reports/trends renders per-bucket drill-down links" do
    @user.expenses.create!(amount: -100_000, date: Date.new(2026, 9, 3),
                           category: @category, money_source: @bank, description: "coffee")

    get reports_trends_path(period: "custom", start_date: Date.new(2026, 9, 1), end_date: Date.new(2026, 9, 30))

    assert_response :success
    container = css_select("[data-spending-trend]").first
    assert container, "trend chart container missing"
    assert_select "[data-testid=report-transactions-modal]"
    assert_select "#reportTransactionsModal .modal-dialog.report-transactions-modal"

    urls = JSON.parse(container["data-spending-trend-urls"])
    third_day = urls[2]
    assert_includes third_day, "period=custom"
    assert_includes third_day, "start_date=2026-09-03"
    assert_includes third_day, "end_date=2026-09-03"
    assert_nil urls[1]

    scripts = Nokogiri::HTML(response.body).css("script[src]").map { |script| script["src"] }
    assert scripts.any? { |src| src.include?("spending_trend") }
    assert scripts.any? { |src| src.include?("reports_transactions_modal") }
  end

  test "GET /reports/by_category wires category rows to the shared transactions modal" do
    @user.expenses.create!(amount: -100_000, date: Date.current, category: @category,
                           money_source: @bank, description: "coffee")

    get reports_by_category_path(period: "this_month")

    assert_response :success
    row = css_select("tr[data-transactions-modal-url]").first
    assert row, "category row should expose a modal URL"
    assert_includes row["data-transactions-modal-url"], "category_id=#{@category.id}"
    assert_select "#reportTransactionsModal"
    assert_select "tr.report-row-link a[href*='category_id=#{@category.id}']"

    scripts = Nokogiri::HTML(response.body).css("script[src]").map { |script| script["src"] }
    assert scripts.any? { |src| src.include?("reports_transactions_modal") }
  end

  test "GET /reports/transactions with modal renders only the drill-down content" do
    @user.expenses.create!(amount: -100_000, date: Date.new(2026, 9, 3),
                           category: @category, money_source: @bank, description: "coffee")

    get reports_transactions_path(period: "custom", start_date: Date.new(2026, 9, 3),
                                  end_date: Date.new(2026, 9, 3), modal: 1)

    assert_response :success
    assert_select "[data-testid=report-transactions-modal-content]"
    assert_select "[data-testid=reports-transactions-table][data-sortable-table]"
    %w[date description category source amount].each do |key|
      assert_select "button[data-sort-key='#{key}']"
    end
    assert_select "h1", count: 0
    assert_select "aside.left-sidebar", count: 0
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

  test "GET /reports/budgets keeps the category filter but hides money sources" do
    get reports_budgets_path

    assert_response :success
    assert_select "form .filters-card"
    assert_select "select[name=category_id]"
    assert_select "select[name=money_source_id]", count: 0
  end

  test "GET /reports/budgets ignores money source params" do
    cash = @user.money_sources.create!(name: "Efectivo", kind: "cash", active: true,
                                       starting_balance: 1_000_000)
    Budget.create!(user: @user, category: @category, monthly_amount: 1_000_000)
    @user.expenses.create!(amount: -100_000, date: Date.current, category: @category,
                           money_source: @bank, description: "bank")
    @user.expenses.create!(amount: -200_000, date: Date.current, category: @category,
                           money_source: cash, description: "cash")

    get reports_budgets_path(period: "this_month", money_source_id: @bank.id)

    assert_response :success
    assert_select "tfoot td", text: "$300.000"
  end

  test "GET /reports/budgets renders the budget control panel" do
    @category.update_column(:icon, "ti-chef-hat")
    Budget.create!(user: @user, category: @category, monthly_amount: 1_000_000)
    @user.expenses.create!(amount: -550_000, date: Date.current, category: @category,
                           money_source: @bank, description: "x")

    get reports_budgets_path(period: "this_month")

    assert_response :success
    assert_select "h1", text: "Presupuesto vs. gasto"
    assert_select "[data-testid=budget-metrics] .budget-metric", count: 4
    assert_select "[data-testid=budget-metric-budget]", text: /\$1\.000\.000/
    assert_select "[data-testid=budget-metric-actual]", text: /\$550\.000/
    assert_select "[data-testid=budget-metric-remaining]", text: /\$450\.000/
    assert_select "[data-testid=budget-metric-usage]", text: /55/
    assert_select "i.ti-chef-hat"
    assert_select "[data-testid=budget-view-table]"
    assert_select "[data-testid=budget-view-chart]"
    assert_select "[data-testid=budget-chart-view] #budget-vs-actual-chart"
  end

  test "GET /reports/budgets limits rows and totals to the selected category" do
    other = Category.create!(name: "Educación", is_default: true, category_type: "expense")
    Budget.create!(user: @user, category: @category, monthly_amount: 1_000_000)
    Budget.create!(user: @user, category: other, monthly_amount: 2_000_000)
    @user.expenses.create!(amount: -100_000, date: Date.current, category: @category,
                           money_source: @bank, description: "selected")
    @user.expenses.create!(amount: -250_000, date: Date.current, category: other,
                           money_source: @bank, description: "other")

    get reports_budgets_path(period: "this_month", category_id: @category.id)

    assert_response :success
    assert_select "[data-testid=budget-metric-budget]", text: /\$1\.000\.000/
    assert_select "[data-testid=budget-metric-actual]", text: /\$100\.000/
    assert_select "tbody tr", count: 1
    assert_select ".budget-category-name", text: @category.name
    assert_select ".budget-category-name", text: other.name, count: 0
  end

  test "GET /reports/budgets treats a custom cycle range as one cycle" do
    @user.update!(financial_cycle_start_day: 20)
    Budget.create!(user: @user, category: @category, monthly_amount: 1_500_000)

    get reports_budgets_path(period: "custom", start_date: "2026-10-20", end_date: "2026-11-19")

    assert_response :success
    assert_select "[data-testid=budget-metric-budget]", text: /\$1\.500\.000/
  end

  test "GET /reports/budgets keeps unbudgeted spending in its own section" do
    other = Category.create!(name: "Educación", is_default: true, category_type: "expense",
                             icon: "ti-school")
    Budget.create!(user: @user, category: @category, monthly_amount: 1_000_000)
    @user.expenses.create!(amount: -100_000, date: Date.current, category: @category,
                           money_source: @bank, description: "budgeted")
    @user.expenses.create!(amount: -250_000, date: Date.current, category: other,
                           money_source: @bank, description: "unbudgeted")

    get reports_budgets_path(period: "this_month")

    assert_response :success
    assert_select "[data-testid=budget-unbudgeted]" do
      assert_select "i.ti-school"
      assert_select "td, .budget-unbudgeted-amount", text: /\$250\.000/
      assert_select "[data-testid=budget-unbudgeted-total]", text: /\$250\.000/
    end
    assert_select "[data-testid=budget-metric-budget]", text: /\$1\.000\.000/
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

  test "reports filters omit the kind filter and only list payment sources" do
    card = @user.money_sources.create!(name: "Visa", kind: "credit_card", active: true)
    cash = @user.money_sources.create!(name: "Efectivo", kind: "cash", active: true)
    loan = @user.money_sources.create!(name: "Préstamo", kind: "loan", active: true)
    pocket = @user.money_sources.create!(name: "Bolsillo", kind: "pocket", active: true)
    inactive = @user.money_sources.create!(name: "Cuenta inactiva", kind: "account", active: false)

    get reports_by_category_path

    assert_response :success
    assert_select "select[name=kind]", count: 0
    assert_select "select[name=money_source_id] option[value='#{@bank.id}']", count: 1
    assert_select "select[name=money_source_id] option[value='#{card.id}']", count: 1
    assert_select "select[name=money_source_id] option[value='#{cash.id}']", count: 1
    assert_select "select[name=money_source_id] option[value='#{loan.id}']", count: 0
    assert_select "select[name=money_source_id] option[value='#{pocket.id}']", count: 0
    assert_select "select[name=money_source_id] option[value='#{inactive.id}']", count: 0
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
    assert_select "table[data-sortable-table]", count: 0
    assert_select "button[data-sort-key]", count: 0
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
