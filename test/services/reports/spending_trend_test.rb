# frozen_string_literal: true

require "test_helper"

class ReportsSpendingTrendTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Trend User", email: "reports_trend_test@example.com", password: "password123")
    @food = Category.create!(name: "Alimentación", is_default: true, category_type: "expense")
    @transport = Category.create!(name: "Transporte", is_default: true, category_type: "expense")
    @bank = @user.money_sources.create!(name: "Davibank", kind: "account", active: true)
    @loan = @user.money_sources.create!(name: "Rotativo", kind: "loan", active: true)
    @period = Reports::Period.new(preset: "this_month", date: Date.new(2026, 9, 15))
    @filter = Reports::Filter.new(user: @user, period: @period)
  end

  def expense(amount, date:, category: @food, source: @bank)
    Expense.create!(user: @user, category: category, money_source: source, amount: amount,
                    date: date, description: "x")
  end

  def trend(period = @period, filter = @filter)
    Reports::SpendingTrend.new(user: @user, filter: filter).call
  end

  test "daily buckets for a monthly period, zero-filled" do
    expense(-210_000, date: Date.new(2026, 9, 3))
    expense(-80_000, date: Date.new(2026, 9, 3))
    expense(-120_000, date: Date.new(2026, 9, 1))

    data = trend

    assert_equal :day, data[:bucket]
    first = data[:series].first
    assert_equal "01/09/2026", first[:label]
    assert_equal 120_000.to_d, first[:total]
    third = data[:series][2]
    assert_equal 290_000.to_d, third[:total]
    assert_equal 2, third[:count]
    assert_equal 30, data[:series].size
    assert_equal 0.to_d, data[:series][1][:total]
  end

  test "monthly buckets for a 12-month period" do
    period = Reports::Period.new(preset: "last_12_months", date: Date.new(2026, 9, 15))
    expense(-4_800_000, date: Date.new(2026, 5, 12))
    expense(-4_200_000, date: Date.new(2026, 5, 20))
    expense(-2_000_000, date: Date.new(2026, 4, 3))

    filter = Reports::Filter.new(user: @user, period: period)
    data = Reports::SpendingTrend.new(user: @user, filter: filter).call

    assert_equal :month, data[:bucket]
    assert_equal 12, data[:series].size
    may = data[:series][7]
    assert_equal "May", may[:label]
    assert_equal 9_000_000.to_d, may[:total]
    april = data[:series][6]
    assert_equal 2_000_000.to_d, april[:total]
  end

  test "weekly buckets for a 3-month period" do
    period = Reports::Period.new(preset: "last_3_months", date: Date.new(2026, 9, 15))
    filter = Reports::Filter.new(user: @user, period: period)
    data = Reports::SpendingTrend.new(user: @user, filter: filter).call

    assert_equal :week, data[:bucket]
    assert data[:series].size > 8
  end

  test "category filter narrows the series" do
    expense(-210_000, date: Date.new(2026, 9, 3), category: @food)
    expense(-80_000, date: Date.new(2026, 9, 3), category: @transport)
    scoped_filter = Reports::Filter.new(user: @user, period: @period, category_id: @food.id)

    data = Reports::SpendingTrend.new(user: @user, filter: scoped_filter).call

    assert_equal 210_000.to_d, data[:series][2][:total]
  end

  test "debt payments are excluded from the trend" do
    installment = expense(-2_800_000, date: Date.new(2026, 9, 3))
    Payment.create!(user: @user, expense: installment, money_source: @loan, amount: 2_800_000,
                    principal_amount: 2_800_000)

    data = trend

    assert_equal 0.to_d, data[:series][2][:total]
    assert_equal 0.to_d, data[:total]
  end

  test "totals the whole period" do
    expense(-210_000, date: Date.new(2026, 9, 3))
    expense(-120_000, date: Date.new(2026, 9, 1))

    assert_equal 330_000.to_d, trend[:total]
  end

  test "empty period yields a zero-filled series" do
    data = trend

    assert_equal 30, data[:series].size
    assert data[:series].all? { |point| point[:total].zero? }
    assert_equal 0.to_d, data[:total]
  end
end
