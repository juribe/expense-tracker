# frozen_string_literal: true

require "test_helper"

class ReportsPerspectivesRecommendationsTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Perspectives Recommendations",
                         email: "perspectives_recs_#{SecureRandom.hex(4)}@example.com", password: "password123")
    @food = Category.create!(name: "Restaurantes Recs", is_default: true, category_type: "expense")
    @transport = Category.create!(name: "Transporte Recs", is_default: true, category_type: "expense")
    @income_category = Category.create!(name: "Salario Recs", is_default: true, category_type: "income")
    @bank = @user.money_sources.create!(name: "Cuenta Recs", kind: "account", active: true,
                                        starting_balance: 100_000_000)
    @period = Reports::Period.new(preset: "this_month", date: Date.new(2026, 9, 15))
    @filter = Reports::Filter.new(user: @user, period: @period)
  end

  def expense(amount, date:, category: @food, source: @bank)
    Expense.create!(user: @user, category: category, money_source: source, amount: -amount.to_d.abs,
                    date: date, description: "gasto")
  end

  def income(amount, date:)
    Income.create!(user: @user, category: @income_category, money_source: @bank, amount: amount.to_d,
                   date: date, description: "ingreso")
  end

  def recommendations(filter: @filter)
    metrics = Reports::Perspectives::Metrics.new(user: @user, filter: filter).call
    comparison = Reports::Perspectives::Comparison.new(metrics: metrics).call
    findings = Reports::Perspectives::Findings.new(user: @user, filter: filter, metrics: metrics,
                                                   comparison: comparison).call

    Reports::Perspectives::Recommendations.new(user: @user, metrics: metrics, comparison: comparison,
                                               findings: findings).call
  end

  def keys(filter: @filter)
    recommendations(filter: filter).map { |row| row[:key] }
  end

  test "recommends a budget for a growing category without an existing budget" do
    expense(1_000_000, date: Date.new(2026, 8, 10))
    expense(2_000_000, date: Date.new(2026, 9, 10))
    expense(500_000, date: Date.new(2026, 9, 12), category: @transport)

    recommendation = recommendations.find { |row| row[:key] == :budget_growth }

    assert recommendation
    assert_includes recommendation[:title], @food.name
    assert_equal :budgets, recommendation[:action][:key]
    assert_equal @food.id, recommendation[:action][:category_id]
  end

  test "does not recommend a budget that already exists" do
    Budget.create!(user: @user, category: @food, monthly_amount: 1_500_000)
    expense(1_000_000, date: Date.new(2026, 8, 10))
    expense(2_000_000, date: Date.new(2026, 9, 10))

    refute_includes keys, :budget_growth
  end

  test "recommends using the surplus only as a conditional action" do
    income(5_000_000, date: Date.new(2026, 9, 2))
    expense(1_000_000, date: Date.new(2026, 8, 10))
    expense(1_000_000, date: Date.new(2026, 9, 10))

    recommendation = recommendations.find { |row| row[:key] == :savings }

    assert recommendation
    assert_equal :goals, recommendation[:action][:key]
    refute_includes recommendation[:body], "$4.000.000"
  end

  test "recommends reviewing a source that concentrates spending" do
    expense(900_000, date: Date.new(2026, 8, 10))
    expense(900_000, date: Date.new(2026, 9, 10))
    expense(100_000, date: Date.new(2026, 9, 12), category: @transport, source: @bank)

    recommendation = recommendations.find { |row| row[:key] == :source_concentration }

    assert recommendation
    assert_equal :money_sources, recommendation[:action][:key]
  end

  test "recommendations are unique and capped" do
    income(5_000_000, date: Date.new(2026, 9, 2))
    expense(1_000_000, date: Date.new(2026, 8, 10))
    expense(2_000_000, date: Date.new(2026, 9, 10))
    expense(100_000, date: Date.new(2026, 9, 12), category: @transport)

    result = recommendations

    assert result.size <= Reports::Perspectives::Thresholds::MAX_RECOMMENDATIONS
    assert_equal result.size, result.map { |row| row[:key] }.uniq.size
    assert result.all? { |row| row[:title].present? && row[:body].present? && row[:action][:key] }
  end

  test "does not duplicate a recurring finding as a recommendation" do
    [ 7, 8, 9 ].each do |month|
      Expense.create!(user: @user, category: @food, money_source: @bank, amount: -500_000,
                      date: Date.new(2026, month, 12), description: "Spotify")
    end
    expense(1_000_000, date: Date.new(2026, 8, 10))
    expense(1_000_000, date: Date.new(2026, 9, 10))

    refute_includes keys, :recurring
  end

  test "without enough data it only suggests keeping records" do
    result = recommendations

    assert_equal [ :review_movements ], result.map { |row| row[:key] }
    assert_equal :transactions, result.first[:action][:key]
  end
end
