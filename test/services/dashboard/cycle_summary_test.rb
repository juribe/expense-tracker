# frozen_string_literal: true

require "test_helper"

class Dashboard::CycleSummaryTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @user = User.create!(name: "Test User", email: "cycle_summary_test@example.com", password: "password123")
    @category = Category.create!(name: "Transporte", is_default: true, category_type: "expense")
    @other_category = Category.create!(name: "Compras", is_default: true, category_type: "expense")
    @span = Date.new(2026, 10, 1)..Date.new(2026, 10, 31)
    @previous_span = Date.new(2026, 9, 1)..Date.new(2026, 9, 30)
  end

  def summary
    Dashboard::CycleSummary.new(user: @user, span: @span, previous_span: @previous_span).call
  end

  def create_expense(amount:, date:, category: @category)
    Expense.create!(user: @user, category: category, amount: amount, date: date, description: "Gasto")
  end

  test "reports income, expense and net totals for the span" do
    Income.create!(user: @user, category: @category, amount: 12_450_000, date: Date.new(2026, 10, 5), description: "Salario")
    create_expense(amount: 869_396, date: Date.new(2026, 10, 6))

    result = summary

    assert_in_delta 12_450_000, result[:income_total], 0.01
    assert_in_delta 869_396, result[:expense_total], 0.01
    assert_in_delta 12_450_000 - 869_396, result[:net_total], 0.01
  end

  test "expense count includes every transaction of the span" do
    3.times { |i| create_expense(amount: 10_000, date: Date.new(2026, 10, i + 1)) }

    assert_equal 3, summary[:expense_count]
  end

  test "deltas compare against the previous span using absolute values" do
    Income.create!(user: @user, category: @category, amount: 10_000_000, date: Date.new(2026, 9, 5), description: "Salario")
    create_expense(amount: 1_000_000, date: Date.new(2026, 9, 10))
    Income.create!(user: @user, category: @category, amount: 12_450_000, date: Date.new(2026, 10, 5), description: "Salario")
    create_expense(amount: 869_396, date: Date.new(2026, 10, 6))

    result = summary

    assert_in_delta -13.06, result[:expense_delta_pct], 0.05
    net_current = 12_450_000 - 869_396
    net_previous = 10_000_000 - 1_000_000
    assert_in_delta((net_current - net_previous).to_f / net_previous * 100, result[:net_delta_pct], 0.01)
  end

  test "deltas are nil when the previous span has no expenses" do
    create_expense(amount: 100_000, date: Date.new(2026, 10, 5))

    assert_nil summary[:expense_delta_pct]
  end

  test "evolution is a zero-filled daily series covering the whole span" do
    create_expense(amount: 220_000, date: Date.new(2026, 10, 5))
    Income.create!(user: @user, category: @category, amount: 1_000_000, date: Date.new(2026, 10, 5), description: "Salario")

    result = summary

    assert_equal 31, result[:evolution].size
    assert_equal [ Date.new(2026, 10, 1), 0, 0 ], [ result[:evolution].first[:date], result[:evolution].first[:income], result[:evolution].first[:expense] ]
    day5 = result[:evolution][4]
    assert_equal 1_000_000, day5[:income]
    assert_equal 220_000, day5[:expense]
  end

  test "top_categories ranks by amount with percentage of the total" do
    create_expense(amount: 520_000, date: Date.new(2026, 10, 2), category: @category)
    create_expense(amount: 298_000, date: Date.new(2026, 10, 3), category: @other_category)

    result = summary

    assert_equal [ "Transporte", "Compras" ], result[:top_categories].map { |c| c[:name] }
    assert_in_delta 520_000, result[:top_categories].first[:total], 0.01
    assert_in_delta 63.6, result[:top_categories].first[:percentage], 0.01
  end

  test "cycle progress counts days elapsed within the span" do
    travel_to Date.new(2026, 10, 18) do
      result = summary
      assert_equal 18, result[:days_elapsed]
      assert_equal 31, result[:days_total]
      assert_equal 58, result[:period_progress_pct].round
    end
  end

  test "projected spend extrapolates the daily rate to the whole span" do
    create_expense(amount: 1_800_000, date: Date.new(2026, 10, 6))

    travel_to Date.new(2026, 10, 18) do
      result = summary
      projected = 1_800_000 * 31 / 18.0
      assert_in_delta projected, result[:projected_spend], 0.01
    end
  end

  test "is on track when the projected spend stays under the income" do
    Income.create!(user: @user, category: @category, amount: 12_450_000, date: Date.new(2026, 10, 5), description: "Salario")
    create_expense(amount: 1_800_000, date: Date.new(2026, 10, 6))

    travel_to Date.new(2026, 10, 18) do
      assert_equal true, summary[:on_track]
    end
  end

  test "is over the meta when the projected spend exceeds the income" do
    Income.create!(user: @user, category: @category, amount: 500_000, date: Date.new(2026, 10, 5), description: "Salario")
    create_expense(amount: 900_000, date: Date.new(2026, 10, 6))

    travel_to Date.new(2026, 10, 18) do
      assert_equal false, summary[:on_track]
    end
  end

  test "upcoming payments lists active expense templates due within 10 days" do
    soon = @user.recurring_templates.create!(kind: "expense", amount: 820_000, category: @category, description: "Tarjeta de crédito",
                                             frequency: "monthly", payment_day: (Date.current + 3).day, source: "manual", active: true)
    @user.recurring_templates.create!(kind: "expense", amount: 2_818_000, category: @other_category, description: "Carro",
                                      frequency: "monthly", payment_day: (Date.current + 20).day, source: "manual", active: true)
    @user.recurring_templates.create!(kind: "income", amount: 1_000_000, category: @other_category, description: "Salario",
                                      frequency: "monthly", payment_day: (Date.current + 3).day, source: "manual", active: true)
    @user.recurring_templates.create!(kind: "expense", amount: 999, category: @other_category, description: "Inactivo",
                                      frequency: "monthly", payment_day: (Date.current + 3).day, source: "manual", active: false)

    result = summary

    assert_equal [ soon.id ], result[:upcoming_payments].map { |p| p[:template].id }
    assert_in_delta 820_000, result[:upcoming_payments].first[:amount], 0.01
    assert_equal Date.current + 3, result[:upcoming_payments].first[:next_date]
  end

  test "next_occurrence_date clamps payment days beyond the month end" do
    assert_equal Date.new(2026, 2, 28), Dashboard::CycleSummary.next_occurrence_date(31, from: Date.new(2026, 2, 1))
    assert_equal Date.new(2026, 4, 5), Dashboard::CycleSummary.next_occurrence_date(5, from: Date.new(2026, 3, 30))
    assert_equal Date.new(2026, 3, 15), Dashboard::CycleSummary.next_occurrence_date(15, from: Date.new(2026, 3, 15))
  end
end
