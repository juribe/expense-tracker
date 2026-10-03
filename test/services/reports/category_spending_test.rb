# frozen_string_literal: true

require "test_helper"

class ReportsCategorySpendingTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Cat User", email: "reports_category_test@example.com", password: "password123")
    @food = Category.create!(name: "Alimentación", is_default: true, category_type: "expense")
    @transport = Category.create!(name: "Transporte", is_default: true, category_type: "expense")
    @bank = @user.money_sources.create!(name: "Davibank", kind: "account", active: true)
    @loan = @user.money_sources.create!(name: "Rotativo", kind: "loan", active: true)
    @other = User.create!(name: "Other", email: "reports_category_other@example.com", password: "password123")
    @period = Reports::Period.new(preset: "this_month", date: Date.new(2026, 9, 15))
    @filter = Reports::Filter.new(user: @user, period: @period)
  end

  def expense(amount, category:, date: Date.new(2026, 9, 10), source: @bank, user: @user)
    Expense.create!(user: user, category: category, money_source: source, amount: amount,
                    date: date, description: "x")
  end

  def report
    Reports::CategorySpending.new(user: @user, filter: @filter).call
  end

  test "groups actual spending by category with totals, shares and counts" do
    expense(-1_200_000, category: @food)
    expense(-300_000, category: @food)
    expense(-620_000, category: @transport)
    expense(-50_000, category: @food, user: @other)

    data = report
    food = data[:categories].find { |c| c[:name] == "Alimentación" }
    transport = data[:categories].find { |c| c[:name] == "Transporte" }

    assert_equal 1_500_000.to_d, food[:total]
    assert_equal 2, food[:count]
    assert_in_delta 70.7, food[:share_pct], 0.1
    assert_equal 620_000.to_d, transport[:total]
    assert_equal 2_120_000.to_d, data[:total]
  end

  test "categories are sorted from highest to lowest spending" do
    expense(-100_000, category: @transport)
    expense(-900_000, category: @food)

    names = report[:categories].map { |c| c[:name] }

    assert_equal %w[Alimentación Transporte], names
  end

  test "compares each category against the previous equivalent period" do
    expense(-1_000_000, category: @food)
    expense(-800_000, category: @food, date: Date.new(2026, 8, 10))
    expense(-620_000, category: @transport, date: Date.new(2026, 8, 10))
    expense(-50_000, category: @transport, date: Date.new(2026, 9, 10))

    data = report
    food = data[:categories].find { |c| c[:name] == "Alimentación" }
    transport = data[:categories].find { |c| c[:name] == "Transporte" }

    assert_equal 800_000.to_d, food[:previous]
    assert_in_delta 25.0, food[:delta_pct], 0.1
    assert_equal 620_000.to_d, transport[:previous]
    assert_in_delta(-91.9, transport[:delta_pct], 0.1)
  end

  test "debt payments are not classified as category spending" do
    installment = expense(-2_800_000, category: @food)
    Payment.create!(user: @user, expense: installment, money_source: @loan, amount: 2_800_000,
                    principal_amount: 2_800_000)

    data = report

    assert_empty data[:categories]
    assert_equal 0.to_d, data[:total]
  end

  test "respects the category filter" do
    expense(-1_200_000, category: @food)
    expense(-620_000, category: @transport)
    scoped_filter = Reports::Filter.new(user: @user, period: @period, category_id: @food.id)

    data = Reports::CategorySpending.new(user: @user, filter: scoped_filter).call

    assert_equal 1, data[:categories].size
    assert_equal 1_200_000.to_d, data[:total]
  end

  test "respects the money source filter" do
    expense(-1_200_000, category: @food)
    card = @user.money_sources.create!(name: "Visa", kind: "credit_card", active: true)
    expense(-620_000, category: @food, source: card)
    scoped_filter = Reports::Filter.new(user: @user, period: @period, credit_card_id: card.id)

    data = Reports::CategorySpending.new(user: @user, filter: scoped_filter).call

    assert_equal 1, data[:categories].size
    assert_equal 620_000.to_d, data[:total]
  end

  test "empty period yields zero totals and no categories" do
    data = report

    assert_empty data[:categories]
    assert_equal 0.to_d, data[:total]
  end

  test "handles large amounts precisely" do
    expense(-99_999_999.99, category: @food)

    data = report

    assert_equal 99_999_999.99.to_d, data[:total]
  end

  test "exposes the drill-down scope of underlying expenses" do
    expense(-1_200_000, category: @food)
    expense(-620_000, category: @transport)

    data = report
    food = data[:categories].find { |c| c[:name] == "Alimentación" }
    drill = food[:scope].call

    assert_equal 1, drill.count
    assert_equal 1_200_000.to_d, drill.first.amount.abs
  end
end
