# frozen_string_literal: true

require "test_helper"

class FinancialSummaryServiceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      name: "Test User",
      email: "financial_summary_test@example.com",
      password: "password123"
    )
    @food = Category.create!(name: "Alimentación", is_default: true, category_type: "expense")
    @housing = Category.create!(name: "Vivienda", is_default: true, category_type: "expense")
    @income_cat = Category.create!(name: "Salario", is_default: true, category_type: "income")
    @month = Date.new(2026, 9, 15)
  end

  def summary(month: @month)
    FinancialSummaryService.new(user: @user, month: month).call
  end

  test "computes income and expenses for current and previous month with deltas" do
    @user.incomes.create!(amount: 10_000_000, date: @month, category: @income_cat)
    @user.incomes.create!(amount: 9_000_000, date: @month << 1, category: @income_cat)
    @user.expenses.create!(amount: 4_000_000, date: @month, category: @food)
    @user.expenses.create!(amount: 2_000_000, date: @month << 1, category: @food)

    data = summary

    assert_equal 10_000_000, data[:income][:total]
    assert_equal 9_000_000, data[:income][:previous]
    assert_in_delta 11.1, data[:income][:delta_pct], 0.1
    assert_equal 4_000_000, data[:expenses][:total]
    assert_equal 2_000_000, data[:expenses][:previous]
    assert_in_delta 100.0, data[:expenses][:delta_pct], 0.01
  end

  test "delta is nil when previous month has no data" do
    @user.expenses.create!(amount: 4_000_000, date: @month, category: @food)
    assert_nil summary[:expenses][:delta_pct]
  end

  test "computes savings and share of income" do
    @user.incomes.create!(amount: 10_000_000, date: @month, category: @income_cat)
    @user.expenses.create!(amount: 7_600_000, date: @month, category: @food)

    savings = summary[:savings]

    assert_equal 2_400_000, savings[:total]
    assert_in_delta 24.0, savings[:pct_of_income], 0.01
  end

  test "computes top expense categories sorted with share percentages" do
    @user.incomes.create!(amount: 10_000_000, date: @month, category: @income_cat)
    @user.expenses.create!(amount: 4_200_000, date: @month, category: @housing)
    @user.expenses.create!(amount: 2_300_000, date: @month, category: @food)

    top = summary[:expenses][:top_categories]

    assert_equal "Vivienda", top.first[:name]
    assert_equal 4_200_000, top.first[:total]
    assert_in_delta 64.6, top.first[:share_pct], 0.1
    assert_in_delta 35.4, top.second[:share_pct], 0.1
  end

  test "computes debt payments of the month" do
    card = @user.money_sources.create!(name: "Visa", kind: "credit_card", active: true)
    expense = @user.expenses.create!(amount: 1_200_000, date: @month, category: @food)
    Payment.create!(user: @user, expense: expense, money_source: card, amount: 1_200_000,
                    principal_amount: 1_200_000)

    assert_equal 1_200_000, summary[:debt][:payments]
  end

  test "computes card utilization across active credit cards" do
    visa = @user.money_sources.create!(name: "Visa", kind: "credit_card", active: true)
    visa.create_credit_account!(credit_limit: 5_000_000)
    # after_commit balance sync does not run inside transactional tests.
    visa.update_column(:cached_balance, -3_600_000) # rubocop:disable Rails/SkipsModelValidations

    assert_in_delta 72.0, summary[:debt][:utilization_pct], 0.01
  end

  test "utilization is nil without credit limits" do
    assert_nil summary[:debt][:utilization_pct]
  end

  test "cycle period spans the pay cycle and compares against the previous cycle" do
    @user.update!(financial_cycle_start_day: 20)
    cycle = PayCycle.containing(@user, Date.new(2026, 11, 2))

    @user.incomes.create!(amount: 10_000_000, date: Date.new(2026, 10, 20), category: @income_cat)
    @user.expenses.create!(amount: 3_000_000, date: Date.new(2026, 11, 3), category: @food)
    # Calendar-month expenses outside the cycle must not count.
    @user.expenses.create!(amount: 999_000, date: Date.new(2026, 11, 25), category: @food)
    @user.expenses.create!(amount: 2_000_000, date: Date.new(2026, 10, 5), category: @food)

    data = FinancialSummaryService.new(user: @user, cycle: cycle).call

    assert_equal "2026-10-20", data[:period_key]
    assert_equal 3_000_000, data[:expenses][:total]
    assert_equal 2_000_000, data[:expenses][:previous]
    assert_equal 10_000_000, data[:income][:total]
  end
end
