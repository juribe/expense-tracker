# frozen_string_literal: true

require "test_helper"

class ReportsSpendingTrendTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Trend User", email: "reports_trend_test@example.com", password: "password123")
    @food = Category.create!(name: "Alimentación", is_default: true, category_type: "expense")
    @transport = Category.create!(name: "Transporte", is_default: true, category_type: "expense")
    @bank = @user.money_sources.create!(name: "Davibank", kind: "account", active: true, starting_balance: 1_000_000_000)
    @loan = @user.money_sources.create!(name: "Rotativo", kind: "loan", active: true)
    @period = Reports::Period.new(preset: "this_month", date: Date.new(2026, 9, 15))
    @filter = Reports::Filter.new(user: @user, period: @period)
  end

  def expense(amount, date:, category: @food, source: @bank)
    Expense.create!(user: @user, category: category, money_source: source, amount: amount,
                    date: date, description: "x")
  end

  def trend(period = @period, filter = @filter, granularity: nil)
    Reports::SpendingTrend.new(user: @user, filter: filter, granularity: granularity).call
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
    assert_equal "Mayo 2026", may[:label]
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

  test "average daily uses elapsed calendar days, not days with movements" do
    expense(-300_000, date: Date.new(2026, 9, 3))

    data = travel_to(Date.new(2026, 9, 15)) { trend }

    assert_equal 15, data[:elapsed_days]
    assert_equal 20_000.to_d, data[:average_daily]
    assert_equal 1, data[:days_with_expenses]
  end

  test "average daily uses the whole period once it has finished" do
    expense(-300_000, date: Date.new(2026, 9, 3))

    data = travel_to(Date.new(2026, 10, 1)) { trend }

    assert_equal 30, data[:elapsed_days]
    assert_equal 10_000.to_d, data[:average_daily]
  end

  test "peak day and days with expenses describe real daily spending" do
    expense(-200_000, date: Date.new(2026, 9, 3))
    expense(-100_000, date: Date.new(2026, 9, 3))
    expense(-50_000, date: Date.new(2026, 9, 5))

    data = travel_to(Date.new(2026, 9, 15)) { trend }

    assert_equal 2, data[:days_with_expenses]
    assert_equal Date.new(2026, 9, 3), data[:peak][:date]
    assert_equal 300_000.to_d, data[:peak][:total]
    assert_equal 2, data[:peak][:count]
  end

  test "granularity overrides the automatic bucket" do
    expense(-100_000, date: Date.new(2026, 9, 3))
    expense(-200_000, date: Date.new(2026, 9, 10))

    assert_equal :week, trend(granularity: "week")[:bucket]
    assert_equal :month, trend(granularity: "month")[:bucket]
    assert_equal :day, trend(granularity: "unsupported")[:bucket]
  end

  test "week and month groupings keep every transaction exactly once" do
    period = Reports::Period.new(preset: "custom", start_date: Date.new(2026, 8, 20),
                                 end_date: Date.new(2026, 9, 15))
    filter = Reports::Filter.new(user: @user, period: period)
    expense(-100_000, date: Date.new(2026, 8, 25))
    expense(-200_000, date: Date.new(2026, 9, 2))
    expense(-300_000, date: Date.new(2026, 9, 10))
    expense(-50_000, date: Date.new(2026, 9, 10))

    daily = Reports::SpendingTrend.new(user: @user, filter: filter, granularity: "day").call
    weekly = Reports::SpendingTrend.new(user: @user, filter: filter, granularity: "week").call
    monthly = Reports::SpendingTrend.new(user: @user, filter: filter, granularity: "month").call

    assert_equal daily[:total], weekly[:series].sum { |point| point[:total] }
    assert_equal daily[:total], monthly[:series].sum { |point| point[:total] }
    assert_equal daily[:transaction_count], weekly[:series].sum { |point| point[:count] }
    assert_equal daily[:transaction_count], monthly[:series].sum { |point| point[:count] }
    assert_equal 2, monthly[:series].size
    assert_equal "Agosto 2026", monthly[:series].first[:label]
    assert_equal Date.new(2026, 8, 20), monthly[:series].first[:range_start]
    assert_equal Date.new(2026, 8, 31), monthly[:series].first[:range_end]
    assert_equal "Septiembre 2026", monthly[:series].last[:label]
  end

  test "week and month drill-down ranges stay inside the period" do
    period = Reports::Period.new(preset: "custom", start_date: Date.new(2026, 8, 20),
                                 end_date: Date.new(2026, 9, 15))
    filter = Reports::Filter.new(user: @user, period: period)
    expense(-100_000, date: Date.new(2026, 8, 25))

    weekly = Reports::SpendingTrend.new(user: @user, filter: filter, granularity: "week").call
    first_week = weekly[:series].first

    assert_equal Date.new(2026, 8, 20), first_week[:range_start]
    assert_equal Date.new(2026, 8, 23), first_week[:range_end]
    assert weekly[:series].all? { |point| point[:range_start] >= period.range.begin }
    assert weekly[:series].all? { |point| point[:range_end] <= period.range.end }
  end
end
