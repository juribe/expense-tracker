# frozen_string_literal: true

require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Test User",
      email: "dashboard_test@example.com",
      password: "password123"
    )
    @category = Category.create!(name: "Food", is_default: true, category_type: "expense")
    @default_source = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 1_000_000_000)
  end

  test "GET /dashboard renders for authenticated user" do
    sign_in @user
    get dashboard_path
    assert_response :success
    assert_select "[data-testid=dashboard-recent-expenses]"
  end

  test "GET /dashboard renders the goals progress bar width from the saved amount" do
    pocket = @user.money_sources.create!(name: "Bolsillo", kind: "pocket", starting_balance: 1_000_000)
    goal = Goal.create!(user: @user, pocket: pocket, name: "Viaje", target_amount: 2_000_000)
    GoalAllocation.create!(financial_goal: goal, pocket: pocket, amount: 1_000_000, date: Date.current)
    sign_in @user

    get dashboard_path

    assert_response :success
    assert_select ".dashboard-progress .progress-bar.et-w-50", count: 1
  end

  test "sidebar shows the admin section to admin users" do
    admin = User.create!(
      name: "Admin User",
      email: "dashboard_admin@example.com",
      password: "password123",
      admin: true
    )
    sign_in admin

    get dashboard_path

    assert_response :success
    assert_select "a[href='#{expense_playground_path}']", count: 1
    assert_select "a[href='#{expense_evaluations_path}']", count: 1
    assert_match I18n.t("nav.section_admin"), response.body
  end

  test "sidebar hides the admin section from regular users" do
    sign_in @user

    get dashboard_path

    assert_response :success
    assert_select "a[href='#{expense_playground_path}']", count: 0
    assert_select "a[href='#{expense_evaluations_path}']", count: 0
    assert_no_match I18n.t("nav.section_admin"), response.body
  end

  test "GET /dashboard redirects unauthenticated user to sign in" do
    get dashboard_path
    assert_response :redirect
    assert_match(/sign_in/, response.location)
  end

  test "GET /dashboard with invalid month shows flash and defaults to current month" do
    sign_in @user
    get dashboard_path, params: { month: "not-a-date" }
    assert_response :success
    assert_equal I18n.t("dashboard.invalid_month", default: "El mes no es válido; se muestra el mes actual."), flash[:alert]
  end

  test "GET /dashboard with valid month loads that month's data" do
    sign_in @user
    @user.expenses.create!(amount: 25.00, date: Date.new(2026, 3, 15), category: @category, description: "Lunch",
                           money_source: @default_source)
    get dashboard_path, params: { month: "2026-03" }
    assert_response :success
  end

  test "GET /dashboard includes expense summary and budgets" do
    sign_in @user
    @user.expenses.create!(amount: 10.00, date: Date.current, category: @category, description: "Coffee", money_source: @default_source)
    get dashboard_path
    assert_response :success
    assert_select "[data-testid=table]", count: 0
  end

  test "GET /dashboard does not query credit accounts for an accounts-only user" do
    sign_in @user

    queries = dashboard_queries_matching(/FROM "credit_accounts"/i)

    assert_empty queries
  end

  test "GET /dashboard preloads credit accounts once for credit sources" do
    3.times do |index|
      card = @user.money_sources.create!(name: "Tarjeta #{index}", kind: "credit_card", starting_balance: 0)
      card.create_credit_account!(credit_limit: 5_000_000, card_last_four: "123#{index}")
    end
    loan = @user.money_sources.create!(name: "Hipoteca", kind: "loan", starting_balance: 0)
    loan.create_credit_account!(outstanding_balance: 10_000_000)

    sign_in @user

    queries = dashboard_queries_matching(/FROM "credit_accounts"/i)

    assert_operator queries.length, :<=, 1,
      "expected at most one credit_accounts query, got #{queries.length}: #{queries.join(' | ')}"
  end

  test "GET /dashboard does not query credit accounts once per recent expense" do
    3.times do |index|
      card = @user.money_sources.create!(name: "Tarjeta #{index}", kind: "credit_card", starting_balance: 0)
      card.create_credit_account!(credit_limit: 5_000_000, card_last_four: "123#{index}")
      @user.expenses.create!(amount: 10_000, date: Date.current, category: @category,
                             description: "Compra #{index}", money_source: card)
    end

    sign_in @user

    queries = dashboard_queries_matching(/FROM "credit_accounts"/i)

    assert_operator queries.length, :<=, 2,
      "expected at most two credit_accounts queries (position + recent expenses), " \
      "got #{queries.length}: #{queries.join(' | ')}"
  end

  test "GET /dashboard groups the summaries by pay cycle with a configured schedule" do
    sign_in @user
    @user.update!(financial_cycle_start_day: 20)
    # Inside the cycle opened Oct 20 (a bill paid Nov 3).
    @user.expenses.create!(amount: 500_000, date: Date.new(2026, 11, 3), category: @category, description: "Arriendo",
                           money_source: @default_source)
    # Calendar-month expense outside the cycle (belongs to the next cycle).
    @user.expenses.create!(amount: 900_000, date: Date.new(2026, 11, 25), category: @category, description: "Fuera",
                           money_source: @default_source)

    get dashboard_path, params: { cycle: "2026-11-2" }

    assert_response :success
    assert_includes response.body, "Arriendo"
    refute_includes response.body, "Fuera"
  end

  test "GET /dashboard shows the financial cycle banner when cycles are enabled" do
    sign_in @user
    @user.update!(financial_cycle_start_day: 20)
    cycle = PayCycle.containing(@user, Date.new(2026, 10, 25))

    get dashboard_path, params: { cycle: "2026-10-25" }

    assert_response :success
    assert_select "div.cycle-banner" do
      assert_select "strong", text: cycle.label
      assert_select "span", text: cycle.range_label
    end
  end

  test "GET /dashboard hides the cycle banner without a configured schedule" do
    sign_in @user

    get dashboard_path

    assert_response :success
    assert_select "div.cycle-banner", count: 0
  end

  test "GET /dashboard no longer renders the period expense count card nor its chart" do
    sign_in @user
    @user.update!(financial_cycle_start_day: 20)

    get dashboard_path, params: { cycle: "2026-10-25" }

    assert_response :success
    assert_select "h5", text: /Gastos de este ciclo/, count: 0
    assert_select "h5", text: /Gastos de este mes/, count: 0
    assert_select ".dashboard-mini-chart", count: 0
  end

  test "GET /dashboard never renders the raw translations hash" do
    sign_in @user

    get dashboard_path

    assert_response :success
    assert_includes response.body, "Dinero en cuentas"
    refute_includes response.body, "Gastos del periodo seleccionado"
    refute_includes response.body, "{:title=>"
  end

  test "GET /dashboard renders exactly four KPI cards in the requested order" do
    sign_in @user

    get dashboard_path

    assert_response :success
    titles = css_select("a.metric-card .metric-card-title").map { |node| node.text.strip }
    assert_equal [
      "Dinero en cuentas",
      "Ingresos del ciclo",
      "Gastos del ciclo",
      "Gasto proyectado"
    ], titles
    assert_select "a.metric-card[href]", count: 4
  end

  test "GET /dashboard KPI cards link to their related pages" do
    sign_in @user

    get dashboard_path

    assert_response :success
    hrefs = css_select("a.metric-card").map { |node| node["href"] }
    assert_equal [
      money_sources_cash_path,
      incomes_path,
      expenses_path,
      reports_budgets_path
    ], hrefs
  end

  test "GET /dashboard drops the Dinero disponible indicator" do
    sign_in @user

    get dashboard_path

    assert_response :success
    refute_includes response.body, "Dinero disponible"
    assert_select ".metric-card", count: 4
  end

  test "GET /dashboard renders the recent expenses table full width below the main grid" do
    sign_in @user
    @user.expenses.create!(amount: 10.00, date: Date.current, category: @category, description: "Coffee",
                           money_source: @default_source)

    get dashboard_path

    assert_response :success
    assert_select ".dashboard-page [data-testid=dashboard-recent-expenses]", count: 1
    assert_select ".dashboard-main-grid [data-testid=dashboard-recent-expenses]", count: 0
    assert_select ".dashboard-movements [data-testid=dashboard-recent-expenses]", count: 1
  end

  test "GET /dashboard places budgets and categories together below the evolution chart" do
    Budget.create!(user: @user, category: @category, monthly_amount: 100_000, period: "monthly", active: true)
    sign_in @user

    get dashboard_path

    assert_response :success
    assert_select ".dashboard-bottom-grid:not(.dashboard-bottom-grid--single)"
    titles = css_select(".dashboard-bottom-grid h5.card-title").map { |node| node.text.strip }
    assert_equal [ "Presupuesto del ciclo", "Distribución por categoría" ], titles
  end

  test "GET /dashboard gives the category card the full bottom grid when there are no budgets" do
    sign_in @user

    get dashboard_path

    assert_response :success
    assert_select "[data-testid=dashboard-budget]", count: 0
    assert_select ".dashboard-bottom-grid.dashboard-bottom-grid--single [data-testid=dashboard-categories]", count: 1
  end

  test "GET /dashboard keeps the evolution chart and the upcoming payments panel in the main grid" do
    sign_in @user

    get dashboard_path

    assert_response :success
    assert_select ".dashboard-main-column h5.card-title", text: /Evolución de ingresos y gastos/
    assert_select ".dashboard-side-column h5.card-title", text: /Próximos pagos/
  end

  test "GET /dashboard shows the financial summary heading and cycle selector" do
    @user.update!(financial_cycle_start_day: 20)
    cycle = PayCycle.containing(@user, Date.new(2026, 10, 25))

    sign_in @user
    get dashboard_path, params: { cycle: "2026-10-25" }

    assert_response :success
    assert_select ".dash-heading h1", text: "Tu resumen financiero"
    assert_select ".dash-heading p", text: "Así se está moviendo tu dinero durante este ciclo."
    assert_select "form.dash-period-selector select[name=cycle]" do
      assert_select "option[selected][value=?]", cycle.starts.iso8601, text: /#{cycle.label}/
    end
  end

  test "GET /dashboard shows the month selector without a configured schedule" do
    sign_in @user

    get dashboard_path

    assert_response :success
    assert_select "form.dash-period-selector select[name=month]" do
      assert_select "option[selected][value=?]", Date.current.strftime("%Y-%m")
    end
  end

  test "GET /dashboard links to the analysis, budget, category and expenses screens preserving the cycle" do
    @user.update!(financial_cycle_start_day: 20)
    Budget.create!(user: @user, category: @category, monthly_amount: 100_000, period: "monthly", active: true)
    sign_in @user

    get dashboard_path, params: { cycle: "2026-10-25" }

    assert_response :success
    assert_select "a[href=?]", monthly_report_path("2026-10-20"), text: /Ver análisis/
    assert_select "a[href=?]", budgets_path(cycle: "2026-10-20"), text: /Ver presupuesto/
    assert_select "a[href=?]", reports_by_category_path(period: "custom", start_date: "2026-10-20", end_date: "2026-11-19"),
                  text: /Ver todas/
    assert_select "a[href=?]", monthly_expenses_path(period: "2026-10-20", status: "pending"), text: /Ver todos/
    assert_select "a[href=?]", expenses_path(start_date: "2026-10-20", end_date: "2026-11-19"),
                  text: /Ver todos los gastos/
  end

  test "GET /dashboard shows the cycle balance as income minus expenses" do
    income_category = Category.create!(name: "Salario", is_default: true, category_type: "income")
    @user.incomes.create!(amount: 20_000_000, date: Date.new(2026, 11, 3), category: income_category,
                          description: "Salario", money_source: @default_source)
    @user.expenses.create!(amount: 3_000_000, date: Date.new(2026, 11, 4), category: @category,
                           description: "Gastos", money_source: @default_source)

    sign_in @user
    get dashboard_path, params: { month: "2026-11" }

    assert_response :success
    assert_select "[data-testid=dashboard-balance]" do
      assert_select ".dash-balance-mark .ti-activity"
      assert_select ".dash-balance-amount.is-positive", text: "+$17.000.000"
      assert_select ".dash-balance-copy small", text: "Ingresos menos gastos registrados"
    end
  end

  test "GET /dashboard marks a negative cycle balance" do
    @user.expenses.create!(amount: 500_000, date: Date.new(2026, 11, 4), category: @category,
                           description: "Gastos", money_source: @default_source)

    sign_in @user
    get dashboard_path, params: { month: "2026-11" }

    assert_response :success
    assert_select ".dash-balance-amount.is-negative", text: "-$500.000"
  end

  test "GET /dashboard shows the cycle budget progress and remaining amount" do
    other_category = Category.create!(name: "Transporte", is_default: true, category_type: "expense")
    Budget.create!(user: @user, category: @category, monthly_amount: 100_000, period: "monthly", active: true)
    Budget.create!(user: @user, category: other_category, monthly_amount: 200_000, period: "monthly", active: true)
    @user.expenses.create!(amount: 80_000, date: Date.new(2026, 11, 3), category: @category,
                           description: "Comida", money_source: @default_source)
    @user.expenses.create!(amount: 50_000, date: Date.new(2026, 11, 4), category: other_category,
                           description: "Bus", money_source: @default_source)

    sign_in @user
    get dashboard_path, params: { month: "2026-11" }

    assert_response :success
    assert_select "[data-testid=dashboard-budget]" do
      assert_select ".dash-budget-value", text: /\$130\.000/
      assert_select ".dash-budget-value small", text: /\$300\.000/
      assert_select ".dash-budget-bar--normal"
      assert_select ".dash-budget-foot", text: /43% utilizado/
      assert_select ".dash-budget-foot", text: /\$170\.000 disponibles/
    end
  end

  test "GET /dashboard shows the total pending payments with pending and overdue statuses" do
    # Freeze mid-cycle so "Agua" (day 10) is still pending and "Luz" (day 5)
    # is already overdue; otherwise the assertion flips with the calendar date.
    travel_to Time.zone.local(2026, 11, 10, 12) do
      @user.recurring_templates.create!(kind: "expense", amount: 170_000, category: @category,
                                        description: "Agua", frequency: "monthly", payment_day: 10,
                                        source: "manual", active: true)
      @user.recurring_templates.create!(kind: "expense", amount: 50_000, category: @category,
                                        description: "Luz", frequency: "monthly", payment_day: 5,
                                        source: "manual", active: true)

      sign_in @user
      get dashboard_path, params: { month: "2026-11" }

      assert_response :success
      assert_select ".dashboard-side-column" do
        assert_select ".dash-pending-total", text: /\$220\.000/
        assert_select ".dash-payment-status--pending", text: "Pendiente"
        assert_select ".dash-payment-status--overdue", text: "Vencido"
        assert_select ".dash-payment--overdue", text: /Luz/
      end
    end
  end

  test "GET /dashboard does not list payments already made as upcoming" do
    template = @user.recurring_templates.create!(kind: "expense", amount: 170_000, category: @category,
                                                 description: "Agua", frequency: "monthly", payment_day: 10,
                                                 source: "manual", active: true)
    @user.expenses.create!(amount: 50_000, date: Date.new(2026, 11, 10), category: @category,
                           description: "Agua", money_source: @default_source, recurring_template: template,
                           recurring_paid_in_full: true)

    sign_in @user
    get dashboard_path, params: { month: "2026-11" }

    assert_response :success
    assert_select "[data-testid=dashboard-upcoming-payments] .dash-payment-name", text: /Agua/, count: 0
    assert_select "[data-testid=dashboard-upcoming-payments] .dash-pending-total", text: /\$0/
  end

  test "GET /dashboard shows the real money source of every recent movement" do
    debit_card = @user.money_sources.create!(name: "Tarjeta débito", kind: "debit_card", starting_balance: 100_000)
    @user.expenses.create!(amount: 10_000, date: Date.new(2026, 11, 3), category: @category,
                           description: "Café", money_source: @default_source)
    @user.expenses.create!(amount: 20_000, date: Date.new(2026, 11, 4), category: @category,
                           description: "Almuerzo", money_source: debit_card)

    sign_in @user
    get dashboard_path, params: { month: "2026-11" }

    assert_response :success
    assert_select "[data-testid=dashboard-recent-expenses] th", text: "Fuente de dinero"
    assert_select "[data-testid=dashboard-recent-expenses] .dash-source-pill", text: /Cuenta/
    assert_select "[data-testid=dashboard-recent-expenses] .dash-source-pill", text: /Tarjeta débito/
    assert_select "[data-testid=dashboard-recent-expenses] tr[data-expense-drawer]", minimum: 2
    assert_select "#expenseDrawer", count: 1
  end

  test "GET /dashboard keeps the recent expenses card visible without movements" do
    sign_in @user

    get dashboard_path

    assert_response :success
    assert_select "[data-testid=dashboard-recent-expenses]"
    assert_select "[data-testid=dashboard-recent-expenses] .empty-state"
  end

  test "GET /dashboard charts format money values with whole pesos" do
    sign_in @user
    @user.money_sources.create!(name: "Davibank", kind: "account", active: true)
    @user.expenses.create!(amount: -1_234_567, date: Date.current, category: @category, description: "x", money_source: @default_source)

    get dashboard_path

    assert_response :success
    assert_includes response.body, '"prefix":"$"'
    assert_includes response.body, '"thousands":"."'
    assert_includes response.body, '"decimal":","'
    assert_includes response.body, '"round":0'
  end

  # ------------------------------------------------- onboarding setup banner

  test "GET /dashboard shows the onboarding banner with the three setup cards for a new user" do
    sign_in @user

    get dashboard_path

    assert_response :success
    assert_select "section[data-testid=onboarding]" do
      assert_select "h2.card-title", text: I18n.t("onboarding.title")
    end
    %w[initial gmail whatsapp].each do |step|
      assert_select "[data-testid='onboarding-card-#{step}']"
    end
    assert_select "[data-testid=onboarding-dismiss]"
    assert_select "[data-testid=onboarding-skip-all]", count: 1
  end

  test "GET /dashboard hides a permanently skipped card and keeps the others" do
    OnboardingProgress.for_user(@user).skip!(:initial)

    sign_in @user
    get dashboard_path

    assert_response :success
    assert_select "[data-testid=onboarding-card-initial]", count: 0
    assert_select "[data-testid=onboarding-card-gmail]"
    assert_select "[data-testid=onboarding-card-whatsapp]"
  end

  test "GET /dashboard hides the whole banner when every step is skipped" do
    OnboardingProgress.for_user(@user).skip_all!([ "initial", "gmail", "whatsapp" ])

    sign_in @user
    get dashboard_path

    assert_response :success
    assert_select "[data-testid=onboarding]", count: 0
  end

  test "GET /dashboard hides the initial card once the financial setup is completed" do
    @user.financial_setups.create!(status: "completed")

    sign_in @user
    get dashboard_path

    assert_response :success
    assert_select "[data-testid=onboarding-card-initial]", count: 0
    assert_select "[data-testid=onboarding-card-gmail]"
    assert_select "[data-testid=onboarding-card-whatsapp]"
  end

  test "GET /dashboard hides the gmail card with an active connection" do
    @user.gmail_connections.create!(email: "dashboard_setup@example.com", active: true)

    sign_in @user
    get dashboard_path

    assert_response :success
    assert_select "[data-testid=onboarding-card-gmail]", count: 0
    assert_select "[data-testid=onboarding-card-initial]"
    assert_select "[data-testid=onboarding-card-whatsapp]"
  end

  test "GET /dashboard hides the whatsapp card when connected" do
    identity = WhatsappIdentity.create!(phone_number: "573001234567", claimed_by_user: @user, claimed_at: Time.current)
    @user.whatsapp_connections.create!(whatsapp_identity: identity, connected_at: Time.current)

    sign_in @user
    get dashboard_path

    assert_response :success
    assert_select "[data-testid=onboarding-card-whatsapp]", count: 0
    assert_select "[data-testid=onboarding-card-initial]"
    assert_select "[data-testid=onboarding-card-gmail]"
  end

  private

  def dashboard_queries_matching(pattern)
    queries = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:name] == "SCHEMA" || payload[:cached]

      queries << payload[:sql] if payload[:sql].to_s.match?(pattern)
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get dashboard_path
    end

    queries
  end
end
