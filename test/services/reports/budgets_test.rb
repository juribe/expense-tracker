# frozen_string_literal: true

require "test_helper"

class ReportsBudgetsTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Budget User", email: "reports_budget_test@example.com", password: "password123")
    @restaurants = Category.create!(name: "Restaurantes", is_default: true, category_type: "expense")
    @food = Category.create!(name: "Alimentación", is_default: true, category_type: "expense")
    @bank = @user.money_sources.create!(name: "Davibank", kind: "account", active: true)
    @loan = @user.money_sources.create!(name: "Rotativo", kind: "loan", active: true)
    @period = Reports::Period.new(preset: "this_month", date: Date.new(2026, 9, 15))
    @filter = Reports::Filter.new(user: @user, period: @period)
  end

  def expense(amount, category:, date: Date.new(2026, 9, 10), source: @bank)
    Expense.create!(user: @user, category: category, money_source: source, amount: amount,
                    date: date, description: "x")
  end

  def report(period: @period, filter: @filter)
    Reports::Budgets.new(user: @user, filter: filter).call
  end

  test "compares each budget against actual spending for the month" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 800_000)
    expense(-920_000, category: @restaurants)

    data = report
    row = data[:rows].first

    assert_equal 800_000.to_d, row[:budget]
    assert_equal 920_000.to_d, row[:actual]
    assert_equal(-120_000.to_d, row[:remaining])
    assert_in_delta 115.0, row[:pct_used], 0.1
    assert_equal :over_budget, row[:status]
  end

  test "under budget status and remaining" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 800_000)
    expense(-600_000, category: @restaurants)

    row = report[:rows].first

    assert_equal 200_000.to_d, row[:remaining]
    assert_in_delta 75.0, row[:pct_used], 0.1
    assert_equal :on_track, row[:status]
  end

  test "near limit status at 80 percent or more" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 800_000)
    expense(-650_000, category: @restaurants)

    row = report[:rows].first

    assert_in_delta 81.25, row[:pct_used], 0.1
    assert_equal :near_limit, row[:status]
  end

  test "multi-month periods scale the monthly budget by covered months" do
    period = Reports::Period.new(preset: "last_3_months", date: Date.new(2026, 9, 15))
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 800_000)
    expense(-500_000, category: @restaurants, date: Date.new(2026, 7, 10))
    expense(-500_000, category: @restaurants, date: Date.new(2026, 9, 10))

    row = Reports::Budgets.new(user: @user, filter: Reports::Filter.new(user: @user, period: period)).call[:rows].first

    assert_equal 2_400_000.to_d, row[:budget]
    assert_equal 1_000_000.to_d, row[:actual]
  end

  test "consolidated totals across budgets" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 800_000)
    Budget.create!(user: @user, category: @food, monthly_amount: 1_000_000)
    expense(-920_000, category: @restaurants)
    expense(-300_000, category: @food)

    data = report

    assert_equal 1_800_000.to_d, data[:total_budget]
    assert_equal 1_220_000.to_d, data[:total_actual]
    assert_equal 580_000.to_d, data[:total_remaining]
  end

  test "debt payments are not counted as budget spending" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 800_000)
    installment = expense(-2_800_000, category: @restaurants)
    Payment.create!(user: @user, expense: installment, money_source: @loan, amount: 2_800_000,
                    principal_amount: 2_800_000)

    row = report[:rows].first

    assert_equal 0.to_d, row[:actual]
  end

  test "respects the money source filter" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 800_000)
    expense(-500_000, category: @restaurants)
    card = @user.money_sources.create!(name: "Visa", kind: "credit_card", active: true)
    expense(-420_000, category: @restaurants, source: card)
    scoped_filter = Reports::Filter.new(user: @user, period: @period, credit_card_id: card.id)

    row = Reports::Budgets.new(user: @user, filter: scoped_filter).call[:rows].first

    assert_equal 420_000.to_d, row[:actual]
  end

  test "categories without a budget are listed as unbudgeted spending" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 800_000)
    expense(-300_000, category: @food)

    data = report

    assert_equal 1, data[:rows].size
    assert_equal 300_000.to_d, data[:unbudgeted][:total]
    assert_equal @food.id, data[:unbudgeted][:categories].first[:id]
  end

  test "empty period with no budgets yields an empty structure" do
    data = report

    assert_empty data[:rows]
    assert_equal 0.to_d, data[:total_budget]
    assert_nil data[:unbudgeted]
  end

  test "inactive budgets are excluded" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 800_000, active: false)
    expense(-920_000, category: @restaurants)

    data = report

    assert_empty data[:rows]
    assert_equal 920_000.to_d, data[:unbudgeted][:total]
  end
end
