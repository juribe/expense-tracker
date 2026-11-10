# frozen_string_literal: true

require "test_helper"

class ReportsPerspectivesFindingsTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Perspectives Findings", email: "perspectives_findings_#{SecureRandom.hex(4)}@example.com",
                         password: "password123")
    @food = Category.create!(name: "Restaurantes Findings", is_default: true, category_type: "expense")
    @transport = Category.create!(name: "Transporte Findings", is_default: true, category_type: "expense")
    @education = Category.create!(name: "Educación Findings", is_default: true, category_type: "expense")
    @subscription = Category.create!(name: "Suscripciones Findings", is_default: true, category_type: "expense")
    @income_category = Category.create!(name: "Salario Findings", is_default: true, category_type: "income")
    @bank = @user.money_sources.create!(name: "Cuenta Findings", kind: "account", active: true,
                                        starting_balance: 100_000_000)
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

  def findings(filter: @filter)
    metrics = Reports::Perspectives::Metrics.new(user: @user, filter: filter).call
    comparison = Reports::Perspectives::Comparison.new(metrics: metrics).call

    Reports::Perspectives::Findings.new(user: @user, filter: filter, metrics: metrics, comparison: comparison).call
  end

  def types(filter: @filter)
    findings(filter: filter).map { |finding| finding[:type] }
  end

  test "detects overall spending increase and the category that explains it" do
    expense(1_000_000, date: Date.new(2026, 8, 10))
    expense(1_000_000, date: Date.new(2026, 8, 12), category: @transport)
    expense(2_000_000, date: Date.new(2026, 9, 10))
    expense(1_000_000, date: Date.new(2026, 9, 12), category: @transport)
    income(5_000_000, date: Date.new(2026, 9, 2))

    result = findings
    increase = result.find { |finding| finding[:type] == :spending_increase }
    growth = result.find { |finding| finding[:type] == :category_growth }

    assert increase
    assert_equal "attention", increase[:importance]
    assert_includes increase[:metric], "+50"
    assert_includes increase[:explanation], "$1.000.000"
    assert growth
    assert_equal @food.id, growth[:category_id]
    assert_includes growth[:metric], "$1.000.000"
  end

  test "positive reduction when the number of records is comparable" do
    expense(500_000, date: Date.new(2026, 8, 10))
    expense(500_000, date: Date.new(2026, 8, 12), category: @transport)
    expense(400_000, date: Date.new(2026, 9, 10))
    expense(400_000, date: Date.new(2026, 9, 12), category: @transport)

    finding = findings.find { |row| row[:type] == :spending_decrease }

    assert finding
    assert_equal "positive", finding[:importance]
    assert_includes finding[:metric], "-20"
  end

  test "flags a reduction driven by fewer records" do
    10.times { |index| expense(100_000, date: Date.new(2026, 8, index + 1)) }
    expense(100_000, date: Date.new(2026, 9, 10))
    expense(100_000, date: Date.new(2026, 9, 11))

    finding = findings.find { |row| row[:type] == :spending_decrease_records }

    assert finding
    assert_equal "attention", finding[:importance]
    assert_includes finding[:explanation], "menos movimientos"
  end

  test "detects a category reduction" do
    expense(2_000_000, date: Date.new(2026, 8, 10))
    expense(1_000_000, date: Date.new(2026, 9, 10))

    finding = findings.find { |row| row[:type] == :category_reduction }

    assert finding
    assert_equal @food.id, finding[:category_id]
    assert_includes finding[:explanation], "Restaurantes Findings"
  end

  test "detects an unusual expense against the category history" do
    expense(1_000_000, date: Date.new(2026, 8, 10))
    [ 4, 5, 6 ].each { |month| expense(200_000, date: Date.new(2026, month, 10), category: @education) }
    unusual = expense(2_000_000, date: Date.new(2026, 9, 10), category: @education)

    finding = findings.find { |row| row[:type] == :unusual_expense }

    assert finding
    assert_equal "attention", finding[:importance]
    assert_includes finding[:metric], "$2.000.000"
    assert_includes finding[:explanation], "Educación Findings"
    assert_equal unusual.id, finding[:action][:expense_id]
    assert finding[:action][:modal]
  end

  test "does not call an expense unusual without enough history" do
    expense(1_000_000, date: Date.new(2026, 8, 10))
    expense(200_000, date: Date.new(2026, 6, 10), category: @education)
    expense(2_000_000, date: Date.new(2026, 9, 10), category: @education)

    refute_includes types, :unusual_expense
  end

  test "detects recurring payments with enough evidence" do
    [ 7, 8, 9 ].each do |month|
      expense(500_000, date: Date.new(2026, month, 12), category: @subscription, description: "Spotify")
    end
    expense(1_000_000, date: Date.new(2026, 8, 10))
    expense(1_000_000, date: Date.new(2026, 9, 10))

    finding = findings.find { |row| row[:type] == :recurring }

    assert finding
    assert_equal "opportunity", finding[:importance]
    assert_includes finding[:explanation], "pagos recurrentes"
    assert_equal :expenses, finding[:action][:key]
    assert_includes finding[:action][:label], "Spotify"
  end

  test "does not invent recurring payments from casual matches" do
    expense(500_000, date: Date.new(2026, 7, 12), category: @subscription, description: "Ferretería")
    expense(500_000, date: Date.new(2026, 9, 12), category: @subscription, description: "Ferretería")
    expense(1_000_000, date: Date.new(2026, 8, 10))
    expense(1_000_000, date: Date.new(2026, 9, 10))

    refute_includes types, :recurring
  end

  test "detects concentration above the configured share" do
    expense(1_000_000, date: Date.new(2026, 8, 10))
    expense(3_000_000, date: Date.new(2026, 9, 10))
    expense(250_000, date: Date.new(2026, 9, 12), category: @transport)

    finding = findings.find { |row| row[:type] == :concentration }

    assert finding
    assert_equal "opportunity", finding[:importance]
    assert_includes finding[:explanation], "Restaurantes Findings"
    assert_includes finding[:metric], "92"
  end

  test "detects when expenses exceed registered income" do
    expense(1_000_000, date: Date.new(2026, 8, 10))
    expense(2_000_000, date: Date.new(2026, 9, 10))
    income(1_000_000, date: Date.new(2026, 9, 2))

    finding = findings.find { |row| row[:type] == :income_negative }

    assert finding
    assert_equal "attention", finding[:importance]
    assert_includes finding[:explanation], "$1.000.000"
  end

  test "detects a cycle without registered income" do
    expense(1_000_000, date: Date.new(2026, 8, 10))
    expense(2_000_000, date: Date.new(2026, 9, 10))

    finding = findings.find { |row| row[:type] == :no_income }

    assert finding
    assert_includes finding[:explanation], "$2.000.000"
  end

  test "does not report a tiny category only because of its high percentage" do
    tiny = Category.create!(name: "Tiny Findings", is_default: true, category_type: "expense")
    expense(10_000, date: Date.new(2026, 8, 5), category: tiny)
    expense(100_000, date: Date.new(2026, 9, 5), category: tiny)
    expense(1_000_000, date: Date.new(2026, 8, 10), category: @food)
    expense(1_500_000, date: Date.new(2026, 9, 10), category: @food)

    growth = findings.select { |row| row[:type] == :category_growth }

    refute_includes growth.map { |row| row[:category_id] }, tiny.id
    assert_includes growth.map { |row| row[:category_id] }, @food.id
  end

  test "findings are unique, capped and ordered by relevance" do
    expense(1_000_000, date: Date.new(2026, 8, 10))
    expense(1_000_000, date: Date.new(2026, 8, 12), category: @transport)
    expense(2_000_000, date: Date.new(2026, 9, 10))
    expense(1_500_000, date: Date.new(2026, 9, 12), category: @transport)

    result = findings

    assert result.size <= Reports::Perspectives::Thresholds::MAX_FINDINGS
    assert_equal result.size, result.map { |row| [ row[:type], row[:category_id] ] }.uniq.size
    assert_equal result.sort_by { |row| -row[:score] }.map { |row| row[:score] },
                 result.map { |row| row[:score] }
  end

  test "findings respect the category filter" do
    expense(1_000_000, date: Date.new(2026, 8, 10))
    expense(1_000_000, date: Date.new(2026, 8, 12), category: @transport)
    expense(2_000_000, date: Date.new(2026, 9, 10))
    expense(3_000_000, date: Date.new(2026, 9, 12), category: @transport)

    filter = Reports::Filter.new(user: @user, period: @period, category_id: @food.id)
    result = findings(filter: filter)

    assert result.none? { |row| row[:category_id] == @transport.id }
    refute_includes result.map { |row| row[:type] }, :concentration
    refute_includes result.map { |row| row[:type] }, :category_growth
  end

  test "no findings when there is no previous period to compare" do
    expense(1_000_000, date: Date.new(2026, 9, 10))

    assert_empty findings
  end
end
