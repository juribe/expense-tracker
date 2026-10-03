# frozen_string_literal: true

require "test_helper"

class ReportsBaseTest < ActiveSupport::TestCase
  class Probe < Reports::Base
    def actual_count(range = period.range)
      actual_expenses(range).count
    end

    def debt_count(range = period.range)
      debt_expenses(range).count
    end

    def payments_total(range = period.range)
      debt_payment_rows(range).sum(&:amount)
    end
  end

  setup do
    @user = User.create!(name: "Base User", email: "reports_base_test@example.com", password: "password123")
    @card = @user.money_sources.create!(name: "Visa", kind: "credit_card", active: true)
    @loan = @user.money_sources.create!(name: "Rotativo", kind: "loan", active: true)
    @bank = @user.money_sources.create!(name: "Davibank", kind: "account", active: true)
    @food = Category.create!(name: "Alimentación", is_default: true, category_type: "expense")
    @period = Reports::Period.new(preset: "this_month", date: Date.new(2026, 9, 15))
    @filter = Reports::Filter.new(user: @user, period: @period)
    @probe = Probe.new(user: @user, filter: @filter)
  end

  def create_expense(amount, date: Date.new(2026, 9, 10), source: @bank, category: @food)
    Expense.create!(user: @user, category: category, money_source: source, amount: amount, date: date, description: "x")
  end

  test "actual expenses exclude expenses carrying a debt payment" do
    create_expense(-100_000)
    card_payment = create_expense(-800_000, source: @card)
    Payment.create!(user: @user, expense: card_payment, money_source: @loan, amount: 800_000,
                    principal_amount: 700_000, interest_amount: 100_000)

    assert_equal 1, @probe.actual_count
    assert_equal 1, @probe.debt_count
  end

  test "payment rows expose the distribution components" do
    card_payment = create_expense(-800_000, source: @card)
    Payment.create!(user: @user, expense: card_payment, money_source: @loan, amount: 800_000,
                    principal_amount: 700_000, interest_amount: 100_000)

    assert_equal 800_000.to_d, @probe.payments_total
  end

  test "debt payments respect the period range" do
    card_payment = create_expense(-800_000)
    Payment.create!(user: @user, expense: card_payment, money_source: @loan, amount: 800_000,
                    principal_amount: 800_000)

    old_expense = create_expense(-500_000, date: Date.new(2026, 8, 10))
    Payment.create!(user: @user, expense: old_expense, money_source: @loan, amount: 500_000,
                    principal_amount: 500_000)

    assert_equal 1, @probe.debt_count(@period.previous_range)
    assert_equal 500_000.to_d, @probe.payments_total(@period.previous_range)
  end

  test "delta_pct compares two values and nil without previous data" do
    assert_nil Reports::Base.delta_pct(100, 0)
    assert_in_delta 25.0, Reports::Base.delta_pct(500, 400), 0.01
    assert_in_delta(-20.0, Reports::Base.delta_pct(400, 500), 0.01)
  end
end
