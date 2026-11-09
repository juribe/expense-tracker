# frozen_string_literal: true

require "test_helper"

class ReportsCashFlowTrendTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Cash Flow User", email: "reports_cash_flow_test@example.com",
                         password: "password123")
    @food = Category.create!(name: "Alimentación", is_default: true, category_type: "expense")
    @transport = Category.create!(name: "Transporte", is_default: true, category_type: "expense")
    @salary = Category.create!(name: "Salario", is_default: true, category_type: "income")
    @bank = @user.money_sources.create!(name: "Davibank", kind: "account", active: true,
                                        starting_balance: 1_000_000_000)
    @loan = @user.money_sources.create!(name: "Rotativo", kind: "loan", active: true)
    @period = Reports::Period.new(preset: "this_month", date: Date.new(2026, 9, 15))
  end

  def expense(amount, date:, category: @food)
    Expense.create!(user: @user, category: category, money_source: @bank, amount: amount,
                    date: date, description: "x")
  end

  def income(amount, date:, category: @salary)
    Income.create!(user: @user, category: category, money_source: @bank, amount: amount,
                   date: date, description: "x")
  end

  def trend(period = @period, category_id: nil)
    filter = Reports::Filter.new(user: @user, period: period, category_id: category_id)
    Reports::CashFlowTrend.new(user: @user, filter: filter).call
  end

  test "compares income and actual expenses in weekly buckets" do
    income(10_000_000, date: Date.new(2026, 9, 5))
    expense(-1_200_000, date: Date.new(2026, 9, 3))
    installment = expense(-2_800_000, date: Date.new(2026, 9, 3))
    Payment.create!(user: @user, expense: installment, money_source: @loan, amount: 2_800_000,
                    principal_amount: 2_800_000)

    data = trend

    assert_equal :week, data[:bucket]
    assert_equal 10_000_000.to_d, data[:total_income]
    assert_equal 1_200_000.to_d, data[:total_expense]

    week = data[:series].find { |point| point[:date] == Date.new(2026, 9, 1) }
    assert_equal 10_000_000.to_d, week[:income]
    assert_equal 1_200_000.to_d, week[:expense], "debt payments are not consumption spending"
    assert_equal "01/09", data[:series].first[:label]
  end

  test "uses daily buckets for short custom periods" do
    period = Reports::Period.new(preset: "custom", start_date: Date.new(2026, 9, 1),
                                 end_date: Date.new(2026, 9, 10), date: Date.new(2026, 9, 15))
    income(2_000_000, date: Date.new(2026, 9, 3))
    expense(-350_000, date: Date.new(2026, 9, 3))

    data = trend(period)
    point = data[:series].find { |row| row[:date] == Date.new(2026, 9, 3) }

    assert_equal :day, data[:bucket]
    assert_equal 10, data[:series].size
    assert_equal "03/09", point[:label]
    assert_equal 2_000_000.to_d, point[:income]
    assert_equal 350_000.to_d, point[:expense]
  end

  test "groups weeks from the period start instead of calendar weeks" do
    period = Reports::Period.new(preset: "custom", start_date: Date.new(2026, 11, 1),
                                 end_date: Date.new(2026, 11, 30), date: Date.current)
    income(5_000_000, date: Date.new(2026, 11, 1))
    expense(-1_000_000, date: Date.new(2026, 11, 2))

    data = trend(period)
    first_week = data[:series].first

    assert_equal Date.new(2026, 11, 1), first_week[:date]
    assert_equal "01/11", first_week[:label]
    assert_equal 5_000_000.to_d, first_week[:income]
    assert_equal 1_000_000.to_d, first_week[:expense],
                 "movements from the same period week share one bucket"
  end

  test "uses monthly buckets for long periods" do
    period = Reports::Period.new(preset: "last_12_months", date: Date.new(2026, 9, 15))
    income(8_000_000, date: Date.new(2026, 5, 12))
    expense(-1_500_000, date: Date.new(2026, 5, 20))

    data = trend(period)
    may = data[:series].find { |row| row[:date] == Date.new(2026, 5, 1) }

    assert_equal :month, data[:bucket]
    assert_equal 12, data[:series].size
    assert_equal 8_000_000.to_d, may[:income]
    assert_equal 1_500_000.to_d, may[:expense]
  end

  test "zero-fills buckets without movements" do
    data = trend

    assert data[:series].any?
    assert data[:series].all? { |point| point[:income].zero? && point[:expense].zero? }
    assert_equal 0.to_d, data[:total_income]
    assert_equal 0.to_d, data[:total_expense]
  end

  test "respects the category filter" do
    expense(-900_000, date: Date.new(2026, 9, 3), category: @food)
    expense(-300_000, date: Date.new(2026, 9, 3), category: @transport)

    data = trend(@period, category_id: @food.id)

    assert_equal 900_000.to_d, data[:total_expense]
  end
end
