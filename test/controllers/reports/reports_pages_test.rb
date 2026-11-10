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
    assert row, "category row should expose its modal URL"
    assert_includes row["data-transactions-modal-url"], "category_id=#{@category.id}"
    assert_includes row["data-transactions-modal-url"], "period=this_month"
    assert_select "tr.report-category-row-link a[href*='category_id=#{@category.id}']"
    assert_select "#reportTransactionsModal"
    assert_select "a.category-distribution-row[data-transactions-modal-url*='category_id=#{@category.id}']"

    scripts = Nokogiri::HTML(response.body).css("script[src]").map { |script| script["src"] }
    assert scripts.any? { |src| src.include?("reports_transactions_modal") }
  end

  test "GET /reports/by_category renders summary indicators and the distribution bars" do
    @user.expenses.create!(amount: -1_000_000, date: Date.current, category: @category,
                           money_source: @bank, description: "coffee")

    get reports_by_category_path(period: "this_month")

    assert_response :success
    assert_select "[data-testid=category-summary]"
    assert_select "[data-testid=category-total]", text: "$1.000.000"
    assert_select "[data-testid=category-count]", text: "1"
    assert_select "[data-testid=category-transactions]", text: "1"
    assert_select "[data-testid=category-average]", text: "$1.000.000"
    assert_select "[data-testid=category-distribution] .category-distribution-row", minimum: 1
    assert_select "[data-testid=category-table]"
  end

  test "category detail keeps the selected period and only that category" do
    other = Category.create!(name: "Transporte", is_default: true, category_type: "expense")
    @user.expenses.create!(amount: -100_000, date: Date.current, category: @category,
                           money_source: @bank, description: "coffee")
    @user.expenses.create!(amount: -200_000, date: Date.current, category: other,
                           money_source: @bank, description: "bus")

    start_date = Date.current.beginning_of_month
    end_date = Date.current.end_of_month
    get reports_by_category_path(period: "custom", start_date: start_date, end_date: end_date)

    href = css_select("tr[data-transactions-modal-url]")
           .find { |row| row.text.include?(@category.name) }["data-transactions-modal-url"]
    assert_includes href, "period=custom"
    assert_includes href, "start_date=#{start_date.iso8601}"
    assert_includes href, "end_date=#{end_date.iso8601}"
    assert_includes href, "category_id=#{@category.id}"

    get href

    assert_response :success
    assert_select "[data-testid=reports-transactions-table]"
    assert_select "table[data-sortable-table]"
    assert_select "td", text: /100\.000/
    assert_select "td", text: /200\.000/, count: 0
  end

  test "uncategorized category rows open the uncategorized detail without losing the period" do
    Expense.create!(user: @user, category: nil, money_source: @bank, amount: -100_000,
                    date: Date.current, description: "sin categoría")

    get reports_by_category_path(period: "this_month")

    row = css_select("tr[data-transactions-modal-url]")
           .find { |candidate| candidate.text.include?("Sin categoría") }
    href = row["data-transactions-modal-url"]

    assert_includes href, "uncategorized=1"
    assert_includes href, "period=this_month"

    get href

    assert_response :success
    assert_select "td", text: /100\.000/
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
    assert_select "[data-testid=category-total]", text: "$1.234.567"

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

  test "GET /reports/insights renders the perspectives summary, findings, recommendations and evolution" do
    income_category = Category.create!(name: "Salario Perspectives", is_default: true, category_type: "income")
    @user.incomes.create!(amount: 5_000_000, date: Date.new(2026, 9, 2), category: income_category,
                          money_source: @bank, description: "salary")
    @user.expenses.create!(amount: -2_000_000, date: Date.new(2026, 9, 10), category: @category,
                           money_source: @bank, description: "current")
    @user.expenses.create!(amount: -1_000_000, date: Date.new(2026, 8, 10), category: @category,
                           money_source: @bank, description: "previous")

    get reports_insights_path(period: "custom", start_date: "2026-09-01", end_date: "2026-09-30")

    assert_response :success
    assert_select "[data-testid=perspectives-summary]"
    assert_select "[data-testid=perspectives-income]"
    assert_select "[data-testid=perspectives-expenses-total]", text: /\$2\.000\.000/
    assert_select "[data-testid=perspectives-balance]"
    assert_select "[data-testid=perspectives-variation]"
    assert_select "[data-testid=insight]", minimum: 1
    assert_select "[data-testid=perspective-recommendations]"
    assert_select "[data-testid=perspectives-evolution]"
    assert_select "#perspectives-evolution-chart"
    assert_select "a[href*='/reports/trends']"
    assert_select "#reportTransactionsModal"
    assert_not_includes response.body, "translation_missing"
  end

  test "GET /reports/insights applies the category filter to the summary" do
    other = Category.create!(name: "Transporte Perspectives", is_default: true, category_type: "expense")
    @user.expenses.create!(amount: -2_000_000, date: Date.new(2026, 9, 10), category: @category,
                           money_source: @bank, description: "selected")
    @user.expenses.create!(amount: -3_000_000, date: Date.new(2026, 9, 11), category: other,
                           money_source: @bank, description: "other")
    @user.expenses.create!(amount: -1_000_000, date: Date.new(2026, 8, 10), category: @category,
                           money_source: @bank, description: "previous")

    get reports_insights_path(period: "custom", start_date: "2026-09-01", end_date: "2026-09-30",
                              category_id: @category.id)

    assert_response :success
    assert_select "[data-testid=perspectives-expenses-total]", text: /\$2\.000\.000/
    assert_select "[data-testid=perspectives-expenses-total]", text: /\$5\.000\.000/, count: 0
  end

  test "GET /reports/insights renders an empty state without movements" do
    get reports_insights_path

    assert_response :success
    assert_select "[data-testid=perspectives-empty]"
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

  test "GET /reports/transactions renders drill-down with filters and sorting" do
    @user.expenses.create!(amount: -100_000, date: Date.current, category: @category, money_source: @bank, description: "coffee")

    get reports_transactions_path(period: "this_month", category_id: @category.id)
    assert_response :success
    assert_select "table[data-sortable-table]"
    assert_select "button[data-sort-key]", minimum: 5
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

  test "GET /reports/trends renders the period indicators and analysis" do
    travel_to Date.new(2026, 9, 15) do
      @user.expenses.create!(amount: -300_000, date: Date.new(2026, 9, 3),
                             category: @category, money_source: @bank, description: "market")
      @user.expenses.create!(amount: -100_000, date: Date.new(2026, 9, 5),
                             category: @category, money_source: @bank, description: "taxi")

      get reports_trends_path(period: "custom", start_date: Date.new(2026, 9, 1),
                              end_date: Date.new(2026, 9, 30))

      assert_response :success
      assert_select "[data-testid=trend-metrics]"
      assert_select "[data-testid=trend-total]", text: "$400.000"
      assert_select "[data-testid=trend-average]", text: "$26.667"
      assert_select "[data-testid=trend-peak]", text: /300\.000/
      assert_select "[data-testid=trend-peak-note]", text: /3 de septiembre/
      assert_select "[data-testid=trend-days-with-expenses]", text: /2\s*\/\s*15/
      assert_select "[data-testid=trend-insights]"
      assert_select "[data-testid=trend-granularity] a", count: 3
      assert_select ".trend-granularity-btn.is-active", text: "Día"
    end
  end

  test "GET /reports/trends changes the grouping and keeps weekly drill-down ranges" do
    @user.expenses.create!(amount: -100_000, date: Date.new(2026, 9, 3),
                           category: @category, money_source: @bank, description: "coffee")

    get reports_trends_path(period: "custom", start_date: Date.new(2026, 9, 1),
                            end_date: Date.new(2026, 9, 30), granularity: "week")

    assert_response :success
    assert_select ".trend-granularity-btn.is-active", text: "Semana"
    assert_select "input[type=hidden][name=granularity][value=week]"

    container = css_select("[data-spending-trend]").first
    urls = JSON.parse(container["data-spending-trend-urls"])
    assert_includes urls.first, "start_date=2026-09-01"
    assert_includes urls.first, "end_date=2026-09-06"
  end

  test "GET /reports/trends groups a cycle across two months" do
    @user.expenses.create!(amount: -100_000, date: Date.new(2026, 8, 25),
                           category: @category, money_source: @bank, description: "august")
    @user.expenses.create!(amount: -200_000, date: Date.new(2026, 9, 3),
                           category: @category, money_source: @bank, description: "september")

    get reports_trends_path(period: "custom", start_date: Date.new(2026, 8, 20),
                            end_date: Date.new(2026, 9, 15), granularity: "month")

    assert_response :success
    assert_includes response.body, "Agosto 2026"
    assert_includes response.body, "Septiembre 2026"

    container = css_select("[data-spending-trend]").first
    urls = JSON.parse(container["data-spending-trend-urls"])
    assert_includes urls.first, "start_date=2026-08-20"
    assert_includes urls.first, "end_date=2026-08-31"
    assert_includes urls.last, "start_date=2026-09-01"
    assert_includes urls.last, "end_date=2026-09-15"
  end

  test "GET /reports/trends distinguishes an empty period from empty filters" do
    get reports_trends_path

    assert_response :success
    assert_select "[data-testid=trend-empty]", text: /No hay gastos registrados/

    get reports_trends_path(period: "this_month", category_id: @category.id)

    assert_response :success
    assert_select "[data-testid=trend-empty-filtered]", text: /No encontramos gastos con los filtros/
    clear = css_select("[data-testid=trend-empty-filtered] a").first
    assert_includes clear["href"], "period=this_month"
    assert_not_includes clear["href"], "category_id"
  end

  test "clearing report filters keeps the selected period" do
    get reports_trends_path(period: "custom", start_date: Date.new(2026, 9, 1),
                            end_date: Date.new(2026, 9, 30))

    assert_response :success
    clear = css_select(".filters-actions a").first
    assert_includes clear["href"], "period=custom"
    assert_includes clear["href"], "start_date=2026-09-01"
    assert_includes clear["href"], "end_date=2026-09-30"
  end

  test "the trend view-gastos link keeps the period and filters" do
    @user.expenses.create!(amount: -100_000, date: Date.current.beginning_of_month,
                           category: @category, money_source: @bank, description: "coffee")

    get reports_trends_path(period: "this_month", category_id: @category.id)

    assert_response :success
    view_gastos = css_select("a").find { |link| link.text.include?("Ver gastos") }
    assert view_gastos, "Ver gastos link missing"
    assert_includes view_gastos["href"], "period=this_month"
    assert_includes view_gastos["href"], "category_id=#{@category.id}"
  end

  test "GET /reports/trends renders a recoverable error state" do
    original = Reports::SpendingTrend
    failing = Class.new(original) do
      def call
        raise ActiveRecord::StatementInvalid, "boom"
      end
    end

    Reports.send(:remove_const, :SpendingTrend)
    Reports.const_set(:SpendingTrend, failing)
    get reports_trends_path

    assert_response :service_unavailable
    assert_select "[data-testid=trend-error]"
    assert_select "[data-testid=trend-error] a", text: "Reintentar"
  ensure
    Reports.send(:remove_const, :SpendingTrend)
    Reports.const_set(:SpendingTrend, original)
  end

  test "the transactions drill-down excludes debt payments from real spending" do
    loan = @user.money_sources.create!(name: "Crédito", kind: "loan", active: true)
    actual = @user.expenses.create!(amount: -100_000, date: Date.new(2026, 9, 3),
                                    category: @category, money_source: @bank, description: "coffee")
    installment = @user.expenses.create!(amount: -2_800_000, date: Date.new(2026, 9, 4),
                                         category: @category, money_source: @bank, description: "loan")
    Payment.create!(user: @user, expense: installment, money_source: loan, amount: 2_800_000,
                    principal_amount: 2_800_000, date: Date.new(2026, 9, 4))

    assert actual.persisted?

    get reports_transactions_path(period: "custom", start_date: Date.new(2026, 9, 1),
                                  end_date: Date.new(2026, 9, 30))

    assert_response :success
    assert_select "td", text: /100\.000/
    assert_select "td", text: /2\.800\.000/, count: 0
  end

  test "sidebar includes the reports link" do
    get reports_overview_path
    assert_select "a[href='#{reports_overview_path}']"
  end
end
