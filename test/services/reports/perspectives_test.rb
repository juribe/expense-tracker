# frozen_string_literal: true

require "test_helper"

class ReportsPerspectivesTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Perspectives User", email: "perspectives_#{SecureRandom.hex(4)}@example.com",
                         password: "password123")
    @food = Category.create!(name: "Restaurantes Perspectives", is_default: true, category_type: "expense")
    @transport = Category.create!(name: "Transporte Perspectives", is_default: true, category_type: "expense")
    @income_category = Category.create!(name: "Salario Perspectives", is_default: true, category_type: "income")
    @bank = @user.money_sources.create!(name: "Cuenta Perspectives", kind: "account", active: true,
                                        starting_balance: 100_000_000)
    @cash = @user.money_sources.create!(name: "Efectivo Perspectives", kind: "cash", active: true,
                                        starting_balance: 10_000_000)
    @loan = @user.money_sources.create!(name: "Crédito Perspectives", kind: "loan", active: true)
    @period = Reports::Period.new(preset: "this_month", date: Date.new(2026, 9, 15))
    @filter = Reports::Filter.new(user: @user, period: @period)
  end

  def expense(amount, date:, category: @food, source: @bank, description: "gasto")
    Expense.create!(user: @user, category: category, money_source: source, amount: -amount.to_d.abs,
                    date: date, description: description)
  end

  def income(amount, date:)
    Income.create!(user: @user, category: @income_category, money_source: @bank, amount: amount.to_d,
                   date: date, description: "ingreso")
  end

  def metrics(filter: @filter)
    Reports::Perspectives::Metrics.new(user: @user, filter: filter).call
  end

  def comparison(filter: @filter)
    Reports::Perspectives::Comparison.new(metrics: metrics(filter: filter)).call
  end

  def perspectives(filter: @filter)
    Reports::Perspectives.new(user: @user, filter: filter).call
  end

  test "calculates income, real expenses and the period balance" do
    income(3_000_000, date: Date.new(2026, 9, 2))
    income(2_000_000, date: Date.new(2026, 8, 2))
    expense(1_000_000, date: Date.new(2026, 9, 5))
    expense(500_000, date: Date.new(2026, 9, 10), category: @transport)
    expense(800_000, date: Date.new(2026, 8, 10))

    data = metrics

    assert_equal 3_000_000.to_d, data[:income][:total]
    assert_equal 2_000_000.to_d, data[:income][:previous]
    assert_equal 1_500_000.to_d, data[:expenses][:total]
    assert_equal 800_000.to_d, data[:expenses][:previous]
    assert_equal 1_500_000.to_d, data[:balance]
    refute data[:partial]
  end

  test "excludes debt payments and transfers from real expenses" do
    expense(1_000_000, date: Date.new(2026, 9, 5))
    debt_expense = expense(5_000_000, date: Date.new(2026, 9, 7))
    Payment.create!(user: @user, expense: debt_expense, money_source: @loan, amount: 5_000_000,
                    principal_amount: 5_000_000)
    Transfer.create!(user: @user, from_source: @bank, to_source: @cash, amount: 10_000_000,
                     date: Date.new(2026, 9, 8), note: "traslado")

    data = metrics

    assert_equal 1_000_000.to_d, data[:expenses][:total]
    assert_equal 0.to_d, data[:income][:total]
  end

  test "groups category metrics with absolute and percentage changes" do
    expense(1_000_000, date: Date.new(2026, 9, 5))
    expense(500_000, date: Date.new(2026, 9, 10), category: @transport)
    expense(800_000, date: Date.new(2026, 8, 10))

    rows = metrics[:categories]
    food = rows.find { |row| row[:id] == @food.id }
    transport = rows.find { |row| row[:id] == @transport.id }

    assert_equal 1_000_000.to_d, food[:total]
    assert_equal 200_000.to_d, food[:delta]
    assert_equal 25.0, food[:delta_pct]
    assert_equal 500_000.to_d, transport[:total]
    assert_nil transport[:delta_pct]
    assert_in_delta 66.7, food[:share_pct], 0.1
  end

  test "groups source metrics inside the user filters" do
    expense(1_000_000, date: Date.new(2026, 9, 5), source: @bank)
    expense(500_000, date: Date.new(2026, 9, 10), category: @transport, source: @cash)

    rows = metrics[:sources]

    assert_equal 2, rows.size
    assert_equal 1_500_000.to_d, rows.sum { |row| row[:total] }
    assert_in_delta 66.7, rows.find { |row| row[:id] == @bank.id }[:share_pct], 0.1
  end

  test "comparison reports absolute and percentage variation" do
    expense(1_500_000, date: Date.new(2026, 9, 5))
    expense(800_000, date: Date.new(2026, 8, 10))

    data = comparison

    assert data[:available]
    assert_equal 700_000.to_d, data[:delta]
    assert_equal 87.5, data[:delta_pct]
    assert_equal :increase, data[:direction]
  end

  test "comparison does not invent a percentage without a previous base" do
    expense(1_000_000, date: Date.new(2026, 9, 5))

    data = comparison

    refute data[:available]
    assert_nil data[:delta_pct]
    assert_empty data[:top_growth]
  end

  test "top growth prioritizes absolute impact over a high percentage on a tiny category" do
    tiny = Category.create!(name: "Categoría pequeña Perspectives", is_default: true, category_type: "expense")
    expense(10_000, date: Date.new(2026, 8, 5), category: tiny)
    expense(100_000, date: Date.new(2026, 9, 5), category: tiny)
    expense(1_000_000, date: Date.new(2026, 8, 10), category: @food)
    expense(1_500_000, date: Date.new(2026, 9, 10), category: @food)

    rows = comparison[:top_growth]

    assert_equal @food.id, rows.first[:id]
    assert_equal 500_000.to_d, rows.first[:delta]
    refute_includes rows.map { |row| row[:id] }, tiny.id
  end

  test "top reductions identify categories where spending fell" do
    expense(500_000, date: Date.new(2026, 9, 5))
    expense(1_200_000, date: Date.new(2026, 8, 10))

    rows = comparison[:top_reduction]

    assert_equal 1, rows.size
    assert_equal @food.id, rows.first[:id]
    assert_equal(-700_000.to_d, rows.first[:delta])
    assert_equal(-58.3, rows.first[:delta_pct])
  end

  test "compares a partial cycle against the same elapsed days of the previous cycle" do
    partial_period = Reports::Period.new(preset: "custom", start_date: Date.current - 4.days, end_date: Date.current + 5.days)
    filter = Reports::Filter.new(user: @user, period: partial_period)
    expense(1_000_000, date: Date.current - 2.days)
    expense(2_000_000, date: partial_period.previous_range.begin + 1.day)

    data = Reports::Perspectives::Metrics.new(user: @user, filter: filter).call
    compared = Reports::Perspectives::Comparison.new(metrics: data).call

    assert data[:partial]
    assert_equal (Date.current - 4.days)..Date.current, data[:current_range]
    assert_equal 2_000_000.to_d, compared[:previous]
    assert_equal :decrease, compared[:direction]
  end

  test "filters category and money source across the analysis" do
    expense(1_000_000, date: Date.new(2026, 9, 5), source: @bank)
    expense(2_000_000, date: Date.new(2026, 9, 10), category: @transport, source: @cash)
    expense(500_000, date: Date.new(2026, 8, 10), source: @bank)
    income(3_000_000, date: Date.new(2026, 9, 2))

    category_filter = Reports::Filter.new(user: @user, period: @period, category_id: @transport.id)
    source_filter = Reports::Filter.new(user: @user, period: @period, money_source_id: @cash.id)

    assert_equal 2_000_000.to_d, metrics(filter: category_filter)[:expenses][:total]
    assert_equal 3_000_000.to_d, metrics(filter: category_filter)[:income][:total]
    assert_equal 2_000_000.to_d, metrics(filter: source_filter)[:expenses][:total]
    assert_equal 0.to_d, metrics(filter: source_filter)[:income][:total]
    assert_equal 1, metrics(filter: category_filter)[:categories].size
  end

  test "never mixes another user's data" do
    other = User.create!(name: "Other Perspectives", email: "perspectives_other_#{SecureRandom.hex(4)}@example.com",
                         password: "password123")
    other_bank = other.money_sources.create!(name: "Otra cuenta", kind: "account", active: true,
                                             starting_balance: 10_000_000)
    Expense.create!(user: other, category: @food, money_source: other_bank, amount: -9_000_000,
                    date: Date.new(2026, 9, 5), description: "ajeno")
    expense(1_000_000, date: Date.new(2026, 9, 5))

    assert_equal 1_000_000.to_d, metrics[:expenses][:total]
    assert_equal 1, metrics[:categories].size
  end

  test "builds a six period spending evolution honoring filters" do
    expense(100_000, date: Date.new(2026, 4, 10))
    expense(200_000, date: Date.new(2026, 5, 10))
    expense(300_000, date: Date.new(2026, 6, 10))
    expense(400_000, date: Date.new(2026, 7, 10))
    expense(500_000, date: Date.new(2026, 8, 10))
    expense(600_000, date: Date.new(2026, 9, 10))

    data = perspectives[:evolution]

    assert_equal 6, data[:series].size
    assert_equal 600_000.to_d, data[:series].last[:total]
    assert_equal 500_000.to_d, data[:series][-2][:total]
    assert_equal 20.0, data[:delta_pct]
  end

  test "summary is generated from the actual totals" do
    income(5_000_000, date: Date.new(2026, 9, 2))
    expense(3_000_000, date: Date.new(2026, 9, 5))
    expense(2_000_000, date: Date.new(2026, 8, 10))

    summary = perspectives[:summary]

    assert_includes summary, "superan"
    assert_includes summary, "aumentaron"
    assert_includes summary, "$2.000.000"
  end

  test "flags insufficient comparison data when only the current period has movements" do
    expense(1_000_000, date: Date.new(2026, 9, 5))

    data = perspectives

    assert data[:available]
    assert data[:insufficient_data]
    assert_empty data[:findings]
  end

  test "flags partial cycles" do
    period = Reports::Period.new(preset: "this_cycle", date: Date.current)
    filter = Reports::Filter.new(user: @user, period: period)

    data = Reports::Perspectives::Metrics.new(user: @user, filter: filter).call

    assert data[:partial]
  end
end
