# frozen_string_literal: true

require "test_helper"
require "csv"

class MonthlyReportsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "Monthly Reports User", email: "monthly_reports_test@example.com",
                         password: "password123")
    @user.update!(financial_cycle_start_day: 20)
    @account = MoneySource.create!(user: @user, name: "Davibank", kind: "account", starting_balance: 9_000_000_000)
    @category = Category.create!(user: @user, name: "Mercado", category_type: "expense")
    @income_category = Category.create!(user: @user, name: "Salario", category_type: "income")
  end

  def income(amount, date: Date.new(2026, 10, 21), description: "Salario")
    @user.incomes.create!(
      category: @income_category, description: description, amount: amount,
      kind: "income", source: "manual", date: date, money_source: @account
    )
  end

  def expense(amount, date: Date.new(2026, 10, 22), description: "Compra", category: @category)
    @user.expenses.create!(
      category: category, description: description, amount: amount,
      kind: "expense", source: "manual", date: date, money_source: @account
    )
  end

  test "show loads categories without an N+1 query" do
    categories = [ @category, Category.create!(user: @user, name: "Transporte"),
                   Category.create!(user: @user, name: "Ocio") ]
    categories.each_with_index do |category, index|
      expense(50_000, date: Date.new(2026, 10, 21 + index), category: category)
    end
    income(3_000_000, date: Date.new(2026, 10, 25))
    sign_in @user

    category_queries = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:name] == "SCHEMA" || payload[:cached]

      category_queries << payload[:sql] if payload[:sql].match?(/FROM "categories"/i)
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      get monthly_report_path("2026-10-20")
    end

    assert_response :success
    # One preload for the combined movements relation plus one query for the
    # category filter options.
    assert_equal 2, category_queries.size
  end

  test "index uses the shared cycle filter and groups transactions by financial cycle" do
    expense(100_000, date: Date.new(2026, 10, 25))
    expense(50_000, date: Date.new(2026, 9, 15))
    sign_in @user

    travel_to Date.new(2026, 11, 8) do
      get monthly_reports_path
    end

    assert_response :success
    assert_select "select#report-period-select option[value=this_cycle]"
    assert_select "[data-testid=monthly-balance-table] tbody tr", count: 1
    assert_select "[data-testid=monthly-balance-table]", text: /Octubre 2026/
    assert_select "[data-testid=monthly-balance-table]", text: /\$100\.000/
  end

  test "index renders the four cycle indicators the chart and the history" do
    income(5_000_000)
    expense(1_000_000)
    sign_in @user

    travel_to Date.new(2026, 11, 8) do
      get monthly_reports_path
    end

    assert_response :success
    assert_select "[data-testid=cycle-balance-metrics] .report-kpi", count: 4
    assert_select "[data-testid=cycle-income-total]", text: /\$5\.000\.000/
    assert_select "[data-testid=cycle-expense-total]", text: /\$1\.000\.000/
    assert_select "[data-testid=cycle-net-total]", text: /\$4\.000\.000/
    assert_select "[data-testid=cycle-savings-rate]", text: /80,0%/
    assert_select "[data-testid=cycle-balance-chart]", text: /Comportamiento por ciclo/
    assert_select "[data-testid=monthly-balance-table] tbody tr", count: 1
    assert_select "[data-testid=cycle-status]", text: /En curso/
  end

  test "index shows no comparison base when the previous cycle has no values" do
    income(1_000_000)
    sign_in @user

    travel_to Date.new(2026, 11, 8) do
      get monthly_reports_path
    end

    assert_response :success
    assert_select "[data-testid=cycle-income-comparison]", text: /Sin base de comparación/
  end

  test "index shows the required empty state when there are no movements" do
    sign_in @user

    travel_to Date.new(2026, 11, 8) do
      get monthly_reports_path
    end

    assert_response :success
    assert_select "[data-testid=monthly-balance-empty]", text: /Cuando registres ingresos y gastos/
  end

  test "index paginates the cycle history and keeps the period" do
    @user.update!(financial_cycle_start_day: 1)
    10.times { |index| expense(10_000, date: Date.new(2025, index + 1, 15)) }
    sign_in @user

    travel_to Date.new(2025, 10, 20) do
      get monthly_reports_path, params: { period: "custom", start_date: "2025-01-01", end_date: "2025-10-31" }

      assert_response :success
      assert_select "[data-testid=monthly-balance-table] tbody tr", count: 8
      assert_match(/page=2/, response.body)

      get monthly_reports_path, params: { period: "custom", start_date: "2025-01-01", end_date: "2025-10-31", page: 2 }

      assert_response :success
      assert_select "[data-testid=monthly-balance-table] tbody tr", count: 2
      assert_match(/start_date=2025-01-01/, response.body)
    end
  end

  test "show renders only the cycle transactions in a sortable table" do
    expense(100_000, date: Date.new(2026, 10, 25), description: "Dentro del ciclo")
    expense(50_000, date: Date.new(2026, 10, 19), description: "Ciclo anterior")
    sign_in @user

    get monthly_report_path("2026-10-20")

    assert_response :success
    assert_select "[data-sortable-table] [data-sort-key]", count: 5
    assert_select "[data-testid=monthly-balance-transactions-table] tbody tr", count: 1
    assert_select "[data-testid=monthly-balance-transactions-table]", text: /Dentro del ciclo/
    assert_no_match(/Ciclo anterior/, response.body)
  end

  test "show renders cycle indicators summary and filters" do
    income(5_000_000)
    expense(1_000_000, description: "DiDi CO Food")
    sign_in @user

    get monthly_report_path("2026-10-20")

    assert_response :success
    assert_select "[data-testid=cycle-detail-income]", text: /\$5\.000\.000/
    assert_select "[data-testid=cycle-detail-expense]", text: /\$1\.000\.000/
    assert_select "[data-testid=cycle-detail-net]", text: /\$4\.000\.000/
    assert_select "[data-testid=cycle-summary-card]", text: /Resumen del ciclo/
    assert_select "[data-testid=cycle-summary-card]", text: /Tasa de ahorro/
    assert_select "input[name=q]"
    assert_select "select[name=type]"
    assert_select "select[name=category_id]"
  end

  test "show filters by type category and search" do
    other = Category.create!(user: @user, name: "Transporte", category_type: "expense")
    expense(100_000, description: "DiDi CO Food", category: @category)
    expense(50_000, description: "Bus", category: other)
    income(3_000_000, description: "Nómina")
    sign_in @user

    get monthly_report_path("2026-10-20"), params: { type: "expense" }
    assert_select "[data-testid=monthly-balance-transactions-table] tbody tr", count: 2

    get monthly_report_path("2026-10-20"), params: { category_id: other.id }
    assert_select "[data-testid=monthly-balance-transactions-table] tbody tr", count: 1
    assert_select "[data-testid=monthly-balance-transactions-table]", text: /Bus/

    get monthly_report_path("2026-10-20"), params: { q: "didi", type: "expense", category_id: @category.id }
    assert_select "[data-testid=monthly-balance-transactions-table] tbody tr", count: 1
    assert_select "[data-testid=monthly-balance-transactions-table]", text: /DiDi CO Food/
  end

  test "show distinguishes an empty cycle from empty filter results" do
    sign_in @user

    get monthly_report_path("2026-10-20")
    assert_select "[data-testid=cycle-movements-empty]", text: /Este ciclo todavía no tiene movimientos registrados/

    expense(100_000, description: "Compra")
    get monthly_report_path("2026-10-20"), params: { q: "no-existe" }
    assert_select "[data-testid=cycle-movements-no-results]", text: /No encontramos movimientos con estos criterios/
  end

  test "show paginates and keeps the active filters" do
    30.times { |index| expense(10_000, description: "Compra #{index}") }
    sign_in @user

    get monthly_report_path("2026-10-20"), params: { q: "Compra", type: "expense", page: 2 }

    assert_response :success
    assert_select "[data-testid=monthly-balance-transactions-table] tbody tr", count: 5
    assert_match(/q=Compra/, response.body)
    assert_match(/type=expense/, response.body)
  end

  test "show exports only the filtered cycle transactions as CSV" do
    expense(100_000, description: "DiDi CO Food")
    income(3_000_000, description: "Nómina")
    expense(50_000, date: Date.new(2026, 9, 15), description: "Ciclo anterior")
    sign_in @user

    get monthly_report_path("2026-10-20", format: :csv), params: { type: "expense" }

    assert_response :success
    assert_equal "text/csv", response.media_type
    rows = CSV.parse(response.body)
    assert_equal [ "Fecha", "Tipo", "Descripción", "Categoría", "Valor" ], rows.first
    assert_equal [ "2026-10-22", "Gasto", "DiDi CO Food", "Mercado", "-100000.0" ], rows[1]
    assert_equal 2, rows.size
  end

  test "index and show expose exactly the same cycle totals" do
    income(5_000_000)
    expense(1_000_000)
    sign_in @user

    travel_to Date.new(2026, 11, 8) do
      get monthly_reports_path
      assert_select "[data-testid=cycle-income-total]", text: /\$5\.000\.000/
      assert_select "[data-testid=cycle-expense-total]", text: /\$1\.000\.000/
      assert_select "[data-testid=cycle-net-total]", text: /\$4\.000\.000/

      get monthly_report_path("2026-10-20")
      assert_select "[data-testid=cycle-detail-income]", text: /\$5\.000\.000/
      assert_select "[data-testid=cycle-detail-expense]", text: /\$1\.000\.000/
      assert_select "[data-testid=cycle-detail-net]", text: /\$4\.000\.000/
    end
  end

  test "show uses the selected cycle dates and marks a current cycle as in progress" do
    sign_in @user

    travel_to Date.new(2026, 11, 8) do
      get monthly_report_path("2026-10-20")
    end

    assert_response :success
    assert_select "[data-testid=cycle-detail-title]", text: /Octubre 2026/
    assert_select "[data-testid=cycle-detail-range]", text: /20 de octubre.*19 de noviembre de 2026/
    assert_select "[data-testid=cycle-detail-status]", text: /En curso/
  end

  test "does not leak another user's cycle movements" do
    other = User.create!(name: "Other", email: "monthly_reports_other@example.com", password: "password123")
    other.update!(financial_cycle_start_day: 20)
    other_account = other.money_sources.create!(name: "Otro banco", kind: "account", active: true, starting_balance: 1_000_000)
    other_category = Category.create!(user: other, name: "Ajena", category_type: "expense", is_default: false)
    other.expenses.create!(category: other_category, description: "Ajena", amount: 100_000, kind: "expense",
                           source: "manual", date: Date.new(2026, 10, 22), money_source: other_account)
    expense(25_000, description: "Propia")
    sign_in @user

    get monthly_report_path("2026-10-20")

    assert_response :success
    assert_select "[data-testid=monthly-balance-transactions-table]", text: /Propia/
    assert_no_match(/Ajena/, response.body)
  end
end
