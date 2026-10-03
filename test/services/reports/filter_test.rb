# frozen_string_literal: true

require "test_helper"

class ReportsFilterTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Filter User", email: "reports_filter_test@example.com", password: "password123")
    @other_user = User.create!(name: "Other", email: "reports_filter_other@example.com", password: "password123")
    @food = Category.create!(name: "Alimentación", is_default: true, category_type: "expense")
    @transport = Category.create!(name: "Transporte", is_default: true, category_type: "expense")
    @bank = @user.money_sources.create!(name: "Davibank", kind: "account", active: true)
    @card = @user.money_sources.create!(name: "Visa", kind: "credit_card", active: true)
    @loan = @user.money_sources.create!(name: "Rotativo", kind: "loan", active: true)
    @period = Reports::Period.new(preset: "this_month", date: Date.new(2026, 9, 15))
  end

  def filter(params = {})
    Reports::Filter.new(user: @user, period: @period, **params)
  end

  def expense(amount, date: Date.new(2026, 9, 10), category: @food, source: @bank, user: @user)
    Expense.create!(user: user, category: category, money_source: source, amount: amount, date: date, description: "x")
  end

  test "unscoped filter returns every user expense inside the period" do
    expense(-100_000, date: Date.new(2026, 9, 5))
    expense(-200_000, date: Date.new(2026, 8, 5))
    expense(-300_000, date: Date.new(2026, 9, 20), user: @other_user)

    assert_equal [ -100_000.to_d ], filter.expense_scope(@period.range).pluck(:amount)
  end

  test "category filter narrows expenses and ignores foreign categories" do
    expense(-100_000, category: @food)
    expense(-200_000, category: @transport)
    expense(-300_000, category: Category.create!(name: "Otro", category_type: "expense", user: @other_user))

    assert_equal [ -100_000.to_d ], filter(category_id: @food.id).expense_scope(@period.range).pluck(:amount)
  end

  test "money source filter narrows expenses" do
    expense(-100_000, source: @bank)
    expense(-200_000, source: @card)

    assert_equal [ -100_000.to_d ], filter(money_source_id: @bank.id).expense_scope(@period.range).pluck(:amount)
  end

  test "credit card and loan filters resolve to the money source filter" do
    expense(-100_000, source: @card)
    expense(-200_000, source: @loan)

    assert_equal [ -100_000.to_d ], filter(credit_card_id: @card.id).expense_scope(@period.range).pluck(:amount)
    assert_equal [ -200_000.to_d ], filter(loan_id: @loan.id).expense_scope(@period.range).pluck(:amount)
  end

  test "unknown ids degrade to no filter instead of raising" do
    expense(-100_000)

    assert_equal [ -100_000.to_d ], filter(category_id: 999_999).expense_scope(@period.range).pluck(:amount)
  end

  test "kind filter selects which base scope is non-empty" do
    Expense.create!(user: @user, category: @food, amount: -100_000, date: @period.range.first, description: "x")
    Income.create!(user: @user, category: @food, amount: 500_000, date: @period.range.first, description: "x")

    assert_equal 100_000.to_d, filter(kind: "expense").expense_scope(@period.range).sum(:amount).abs
    assert_equal 500_000.to_d, filter(kind: "income").income_scope(@period.range).sum(:amount)
    assert_equal 0.to_d, filter(kind: "expense").income_scope(@period.range).sum(:amount)
    assert_equal 0.to_d, filter(kind: "income").expense_scope(@period.range).sum(:amount)
  end

  test "transfer scope covers transfers touching the filtered source" do
    @user.transfers.create!(from_source: @bank, to_source: @card, amount: 500_000, date: Date.new(2026, 9, 5))
    @user.transfers.create!(from_source: @loan, to_source: @bank, amount: 300_000, date: Date.new(2026, 9, 6))
    @other_user.transfers.create!(from_source: @bank, to_source: @card, amount: 900_000, date: Date.new(2026, 9, 5))

    assert_equal 2, filter.transfer_scope(@period.range).count
    assert_equal 1, filter(money_source_id: @card.id).transfer_scope(@period.range).count
  end

  test "applied filters expose user-facing chips and drop unknown ids" do
    f = filter(category_id: @food.id, money_source_id: @card.id)

    assert_equal %w[category money_source], f.applied_filters
    assert_empty filter.applied_filters
  end

  test "loan filter reports itself as money source chip" do
    assert_equal %w[money_source], filter(loan_id: @loan.id).applied_filters
  end
end
