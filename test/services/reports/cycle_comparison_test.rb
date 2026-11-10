# frozen_string_literal: true

require "test_helper"

class ReportsCycleComparisonTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Cycle Comparison", email: "cycle_comparison_test@example.com",
                         password: "password123")
    @user.update!(financial_cycle_start_day: 20)
    @income_category = Category.create!(name: "Salario", is_default: true, category_type: "income")
    @expense_category = Category.create!(name: "Mercado", is_default: true, category_type: "expense")
    @bank = @user.money_sources.create!(name: "Banco", kind: "account", active: true, starting_balance: 100_000_000)
    @cycle = PayCycle.containing(@user, Date.new(2026, 10, 25))
  end

  def income(amount, date:)
    Income.create!(user: @user, category: @income_category, money_source: @bank, amount: amount,
                   date: date, description: "Ingreso #{date}", source: "manual")
  end

  def expense(amount, date:)
    Expense.create!(user: @user, category: @expense_category, money_source: @bank, amount: -amount.to_d,
                    date: date, description: "Gasto #{date}", source: "manual")
  end

  def comparison
    balance = Reports::CycleBalances.new(user: @user, cycles: [ @cycle ]).call.first
    Reports::CycleComparison.new(user: @user, cycle: @cycle, current_balance: balance).call
  end

  test "compares a completed cycle with the immediately previous cycle" do
    income(5_000_000, date: Date.new(2026, 10, 21))
    expense(1_000_000, date: Date.new(2026, 10, 22))
    income(4_000_000, date: Date.new(2026, 9, 21))
    expense(500_000, date: Date.new(2026, 9, 22))

    data = travel_to(Date.new(2026, 11, 25)) { comparison }

    assert_equal 1_000_000.to_d, data[:income][:amount]
    assert_in_delta 25.0, data[:income][:pct].to_f, 0.001
    assert_equal :up, data[:income][:direction]
    assert data[:income][:base_available]

    assert_equal 500_000.to_d, data[:expense][:amount]
    assert_in_delta 100.0, data[:expense][:pct].to_f, 0.001
    assert_equal :up, data[:expense][:direction]
    refute data[:same_elapsed_days]
  end

  test "reports no comparison base when the previous cycle is zero" do
    income(1_000_000, date: Date.new(2026, 10, 21))

    data = travel_to(Date.new(2026, 11, 25)) { comparison }

    assert_equal 1_000_000.to_d, data[:income][:amount]
    assert_nil data[:income][:pct]
    refute data[:income][:base_available]
    assert_nil data[:expense][:pct]
    refute data[:expense][:base_available]
  end

  test "compares an in-progress cycle against the same elapsed days of the previous one" do
    income(1_000_000, date: Date.new(2026, 10, 21))
    income(500_000, date: Date.new(2026, 9, 21))
    income(3_000_000, date: Date.new(2026, 9, 30))

    data = travel_to(Date.new(2026, 10, 25)) { comparison }

    assert data[:same_elapsed_days]
    assert_equal Date.new(2026, 9, 20)..Date.new(2026, 9, 25), data[:previous_window].to_range
    assert_equal 500_000.to_d, data[:income][:previous]
    assert_in_delta 100.0, data[:income][:pct].to_f, 0.001
  end

  test "a completed cycle compares against the whole previous cycle" do
    income(1_000_000, date: Date.new(2026, 10, 21))
    income(500_000, date: Date.new(2026, 9, 21))
    income(3_000_000, date: Date.new(2026, 9, 30))

    data = travel_to(Date.new(2026, 11, 25)) { comparison }

    refute data[:same_elapsed_days]
    assert_equal Date.new(2026, 9, 20)..Date.new(2026, 10, 19), data[:previous_window].to_range
    assert_equal 3_500_000.to_d, data[:income][:previous]
  end
end
