# frozen_string_literal: true

require "test_helper"

class ReportsOverviewTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Overview User", email: "reports_overview_test@example.com", password: "password123")
    @other = User.create!(name: "Other", email: "reports_overview_other@example.com", password: "password123")
    @food = Category.create!(name: "Alimentación", is_default: true, category_type: "expense")
    @salary = Category.create!(name: "Salario", is_default: true, category_type: "income")
    @bank = @user.money_sources.create!(name: "Davibank", kind: "account", active: true)
    @card = @user.money_sources.create!(name: "Visa", kind: "credit_card", active: true)
    @loan = @user.money_sources.create!(name: "Rotativo", kind: "loan", active: true)
    @savings = @user.money_sources.create!(name: "Ahorros", kind: "account", active: true)
    @period = Reports::Period.new(preset: "this_month", date: Date.new(2026, 9, 15))
    @filter = Reports::Filter.new(user: @user, period: @period)
  end

  def overview
    Reports::Overview.new(user: @user, filter: @filter).call
  end

  def expense(amount, date: Date.new(2026, 9, 10), source: @bank, category: @food, user: @user)
    Expense.create!(user: user, category: category, money_source: source, amount: amount,
                    date: date, description: "x")
  end

  def income(amount, date: Date.new(2026, 9, 5), user: @user)
    Income.create!(user: user, category: @salary, amount: amount, date: date, description: "x")
  end

  def loan_payment(expense, principal:, interest:, insurance: 0, other: 0)
    Payment.create!(user: @user, expense: expense, money_source: @loan, amount: expense.amount.abs,
                    principal_amount: principal, interest_amount: interest,
                    insurance_amount: insurance, other_amount: other)
  end

  test "aggregates income and actual expenses for the period" do
    income(10_000_000)
    income(2_000_000, date: Date.new(2026, 8, 5))
    expense(-1_200_000)
    expense(-300_000)
    expense(-999, user: @other)

    data = overview

    assert_equal 10_000_000.to_d, data[:income][:total]
    assert_equal 1_500_000.to_d, data[:expenses][:total]
  end

  test "debt payments are separated from actual spending" do
    income(10_000_000)
    expense(-1_200_000)
    installment = expense(-2_800_000)
    loan_payment(installment, principal: 2_400_000, interest: 380_000, insurance: 20_000)

    data = overview

    assert_equal 1_200_000.to_d, data[:expenses][:total]
    assert_equal 2_800_000.to_d, data[:debt][:total]
    assert_equal 2_400_000.to_d, data[:debt][:principal]
    assert_equal 380_000.to_d, data[:debt][:interest]
    assert_equal 20_000.to_d, data[:debt][:insurance]
  end

  test "credit card purchases are expenses, transfers into the card are debt payments" do
    expense(-2_100_000, source: @card)
    @user.transfers.create!(from_source: @bank, to_source: @card, amount: 1_400_000,
                            date: Date.new(2026, 9, 20))

    data = overview

    assert_equal 2_100_000.to_d, data[:expenses][:total]
    assert_equal 1_400_000.to_d, data[:debt][:total]
    assert_equal 1_400_000.to_d, data[:transfers][:total]
  end

  test "transfers between accounts are neither expenses nor debt payments" do
    @user.transfers.create!(from_source: @bank, to_source: @savings, amount: 1_000_000,
                            date: Date.new(2026, 9, 20))

    data = overview

    assert_equal 0.to_d, data[:expenses][:total]
    assert_equal 0.to_d, data[:debt][:total]
    assert_equal 1_000_000.to_d, data[:transfers][:total]
    assert_equal 1, data[:transfers][:count]
  end

  test "loan disbursement transfer is not income" do
    @user.transfers.create!(from_source: @loan, to_source: @bank, amount: 5_000_000,
                            date: Date.new(2026, 9, 1))

    data = overview

    assert_equal 0.to_d, data[:income][:total]
    assert_equal 0.to_d, data[:debt][:total]
    assert_equal 5_000_000.to_d, data[:transfers][:total]
  end

  test "loan payment expense is not counted twice when paying card on same day" do
    purchase = expense(-400_000, source: @card)
    card_payment_expense = expense(-400_000)
    Payment.create!(user: @user, expense: card_payment_expense, money_source: @card,
                    amount: 400_000, principal_amount: 400_000)

    data = overview

    assert_equal 400_000.to_d, data[:expenses][:total], "only the purchase is spending"
    assert_equal 400_000.to_d, data[:debt][:total], "only the card payment is debt"
    assert_equal 1, data[:expenses][:count]
  end

  test "net cash flow equals income minus spending minus debt" do
    income(10_000_000)
    expense(-4_000_000)
    installment = expense(-2_800_000)
    loan_payment(installment, principal: 2_400_000, interest: 400_000)

    data = overview

    assert_equal 3_200_000.to_d, data[:net_cash_flow]
  end

  test "reports counts and averages of actual expenses" do
    expense(-1_200_000)
    expense(-300_000)

    data = overview

    assert_equal 2, data[:expenses][:count]
    assert_equal 750_000.to_d, data[:expenses][:average]
  end

  test "compares against the previous equivalent period" do
    income(10_000_000, date: Date.new(2026, 9, 5))
    expense(-4_820_000)
    income(9_000_000, date: Date.new(2026, 8, 5))
    expense(-4_300_000, date: Date.new(2026, 8, 10))

    data = overview

    assert_equal 4_300_000.to_d, data[:expenses][:previous]
    assert_in_delta 12.1, data[:expenses][:delta_pct], 0.1
    assert_equal 9_000_000.to_d, data[:income][:previous]
  end

  test "delta_pct is nil when the previous period had no activity" do
    expense(-100_000)

    data = overview

    assert_nil data[:expenses][:delta_pct]
    assert_equal 0.to_d, data[:expenses][:previous]
  end

  test "empty period yields zeroed structure" do
    data = overview

    assert_equal 0.to_d, data[:income][:total]
    assert_equal 0.to_d, data[:expenses][:total]
    assert_equal 0.to_d, data[:debt][:total]
    assert_equal 0.to_d, data[:transfers][:total]
    assert_equal 0, data[:expenses][:count]
    assert_nil data[:expenses][:average]
  end

  test "respects the category filter" do
    @food2 = Category.create!(name: "Transporte_#{SecureRandom.hex(4)}", category_type: "expense", user: @user)
    expense(-1_200_000, category: @food)
    expense(-300_000, category: @food2)

    scoped_filter = Reports::Filter.new(user: @user, period: @period, category_id: @food.id)
    data = Reports::Overview.new(user: @user, filter: scoped_filter).call

    assert_equal 1_200_000.to_d, data[:expenses][:total]
  end
end
