# frozen_string_literal: true

require "test_helper"

class DebtCapacityMetricsTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Debt Metrics User", email: "debt_metrics_test@example.com", password: "password123")
    @income_category = Category.create!(name: "Salario", category_type: "income", is_default: true)
    @expense_category = Category.create!(name: "Vivienda", category_type: "expense", is_default: true)
    @month = Date.new(2026, 9, 15)
    @user.money_sources.create!(name: "Hipotecario", kind: "loan", active: true).create_credit_account!(
      outstanding_balance: 80_000_000, installment_amount: 2_500_000, interest_rate: 12.0,
      interest_rate_type: "effective_annual"
    )
  end

  test "calculates debt ratio, target margin and alert excess from monthly income" do
    @user.incomes.create!(amount: 10_000_000, date: @month, category: @income_category)

    metrics = metrics_with_expenses(monthly_installments: 3_000_000)

    assert_equal 10_000_000.to_d, metrics[:monthly_income]
    assert_equal 3_000_000.to_d, metrics[:monthly_installments]
    assert_in_delta 30.0, metrics[:debt_ratio], 0.01
    assert_equal 0.to_d, metrics[:available_margin]
    assert_equal 0.to_d, metrics[:excess_over_target]
    assert_equal 0.to_d, metrics[:excess_over_alert]
    assert_equal :healthy, metrics[:status]
  end

  test "classifies ratios between the healthy and alert thresholds as precaution" do
    @user.incomes.create!(amount: 10_000_000, date: @month, category: @income_category)

    metrics = metrics_with_expenses(monthly_installments: 3_500_000)

    assert_in_delta 35.0, metrics[:debt_ratio], 0.01
    assert_equal 0.to_d, metrics[:available_margin]
    assert_equal 500_000.to_d, metrics[:excess_over_target]
    assert_equal 0.to_d, metrics[:excess_over_alert]
    assert_equal :precaution, metrics[:status]
  end

  test "classifies ratios above the alert threshold and reports both excesses" do
    @user.incomes.create!(amount: 10_000_000, date: @month, category: @income_category)

    metrics = metrics_with_expenses(monthly_installments: 4_500_000)

    assert_in_delta 45.0, metrics[:debt_ratio], 0.01
    assert_equal 1_500_000.to_d, metrics[:excess_over_target]
    assert_equal 500_000.to_d, metrics[:excess_over_alert]
    assert_equal :elevated, metrics[:status]
  end

  test "does not calculate a ratio when monthly income is missing or zero" do
    missing_income = metrics_with_expenses(monthly_installments: 2_000_000)

    assert_nil missing_income[:debt_ratio]
    assert_nil missing_income[:available_margin]
    assert_equal :income_required, missing_income[:status]

    zero_income = metrics_with_expenses(monthly_installments: 2_000_000, income: 0)

    assert_nil zero_income[:debt_ratio]
    assert_equal :income_required, zero_income[:status]
  end

  test "keeps the debt margin separate from pressure after essential expenses" do
    @user.incomes.create!(amount: 10_000_000, date: @month, category: @income_category)
    @user.expenses.create!(amount: 6_500_000, date: @month, category: @expense_category)

    metrics = metrics_with_expenses(monthly_installments: 2_000_000)

    assert_equal 1_000_000.to_d, metrics[:available_margin]
    assert_equal 1_500_000.to_d, metrics[:financial_pressure]
    assert_equal 6_500_000.to_d, metrics[:essential_expenses]
    assert_in_delta 65.0, metrics[:essential_expenses_percentage], 0.01
  end

  private

  def metrics_with_expenses(monthly_installments:, income: @user.incomes.in_month(@month).sum(:amount))
    DebtCapacity::Metrics.new(
      income: income,
      monthly_installments: monthly_installments,
      essential_expenses: @user.expenses.in_month(@month).sum(:amount).abs,
      target_percentage: 30,
      alert_percentage: 40
    ).call
  end
end
