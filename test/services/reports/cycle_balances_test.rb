# frozen_string_literal: true

require "test_helper"

class ReportsCycleBalancesTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Cycle Balance", email: "cycle_balance_test@example.com", password: "password123")
    @user.update!(financial_cycle_start_day: 20)
    @income_category = Category.create!(name: "Salario", is_default: true, category_type: "income")
    @expense_category = Category.create!(name: "Mercado", is_default: true, category_type: "expense")
    @gmf_category = Category.create!(name: "4x1.000 (GMF)", is_default: true, category_type: "expense")
    @bank = @user.money_sources.create!(name: "Banco", kind: "account", active: true, starting_balance: 100_000_000)
    @cash = @user.money_sources.create!(name: "Efectivo", kind: "cash", active: true, starting_balance: 10_000_000)
    @card = @user.money_sources.create!(name: "Visa", kind: "credit_card", active: true)
    @card.create_credit_account!(credit_limit: 50_000_000)
    @cycle = PayCycle.containing(@user, Date.new(2026, 10, 25))
  end

  def income(amount, date:, category: @income_category, source: @bank)
    Income.create!(user: @user, category: category, money_source: source, amount: amount,
                   date: date, description: "Ingreso #{date}", source: "manual")
  end

  def expense(amount, date:, category: @expense_category, source: @bank)
    Expense.create!(user: @user, category: category, money_source: source, amount: -amount.to_d,
                    date: date, description: "Gasto #{date}", source: "manual")
  end

  def balances(cycles = [ @cycle ])
    Reports::CycleBalances.new(user: @user, cycles: cycles).call
  end

  test "counts valid incomes and real expenses for the cycle" do
    income(5_000_000, date: Date.new(2026, 10, 21))
    expense(1_000_000, date: Date.new(2026, 10, 22))

    balance = balances.first

    assert_equal 5_000_000.to_d, balance[:income_total]
    assert_equal 1_000_000.to_d, balance[:expense_total]
    assert_equal 4_000_000.to_d, balance[:net_total]
    assert_in_delta 80.0, balance[:savings_rate].to_f, 0.001
    assert_equal 2, balance[:movement_count]
    assert_equal @cycle.starts.iso8601, balance[:key]
  end

  test "keeps a negative net result and a negative savings rate" do
    income(1_000_000, date: Date.new(2026, 10, 21))
    expense(1_500_000, date: Date.new(2026, 10, 22))

    balance = balances.first

    assert_equal(-500_000.to_d, balance[:net_total])
    assert_in_delta(-50.0, balance[:savings_rate].to_f, 0.001)
    assert_equal 2, balance[:movement_count]
  end

  test "savings rate is nil when the cycle has no income" do
    expense(300_000, date: Date.new(2026, 10, 22))

    balance = balances.first

    assert_equal 300_000.to_d, balance[:expense_total]
    assert_nil balance[:savings_rate]
    assert_equal(-300_000.to_d, balance[:net_total])
  end

  test "savings rate is nil for an empty cycle" do
    balance = balances.first

    assert_equal 0.to_d, balance[:income_total]
    assert_equal 0.to_d, balance[:expense_total]
    assert_equal 0.to_d, balance[:net_total]
    assert_nil balance[:savings_rate]
    assert_equal 0, balance[:movement_count]
  end

  test "excludes an expense already applied to a debt from real expenses" do
    debt_expense = expense(500_000, date: Date.new(2026, 10, 23), source: @card)
    Payment.create!(user: @user, expense: debt_expense, money_source: @card, amount: 500_000,
                    principal_amount: 500_000)
    expense(250_000, date: Date.new(2026, 10, 24))

    balance = balances.first

    assert_equal 250_000.to_d, balance[:expense_total]
    assert_equal 1, balance[:movement_count]
  end

  test "internal transfers never inflate income or expenses" do
    income(2_000_000, date: Date.new(2026, 10, 21))
    expense(500_000, date: Date.new(2026, 10, 22))
    Transfer.create!(user: @user, from_source: @bank, to_source: @cash, amount: 1_500_000,
                     date: Date.new(2026, 10, 23))

    balance = balances.first

    assert_equal 2_000_000.to_d, balance[:income_total]
    assert_equal 500_000.to_d, balance[:expense_total]
    assert_equal 2, balance[:movement_count]
  end

  test "counts GMF charges as real expenses" do
    expense(4_000, date: Date.new(2026, 10, 24), category: @gmf_category)

    balance = balances.first

    assert_equal 4_000.to_d, balance[:expense_total]
  end

  test "isolates cycles and transactions by user" do
    other = User.create!(name: "Other", email: "cycle_balance_other@example.com", password: "password123")
    other.update!(financial_cycle_start_day: 20)
    other_bank = other.money_sources.create!(name: "Banco otro", kind: "account", active: true, starting_balance: 10_000_000)
    Income.create!(user: other, category: @income_category, money_source: other_bank, amount: 9_000_000,
                   date: Date.new(2026, 10, 21), description: "Ajeno", source: "manual")
    expense(100_000, date: Date.new(2026, 10, 22))

    balance = balances.first

    assert_equal 0.to_d, balance[:income_total]
    assert_equal 100_000.to_d, balance[:expense_total]
  end

  test "derives cycle status from the real dates" do
    travel_to Date.new(2026, 10, 25) do
      assert_equal :in_progress, balances.first[:status]
      assert balances.first[:current]
    end

    travel_to Date.new(2026, 11, 25) do
      assert_equal :completed, balances.first[:status]
      refute balances.first[:current]
    end

    future = PayCycle.containing(@user, Date.new(2026, 12, 25))
    travel_to Date.new(2026, 11, 25) do
      future_balance = balances([ future ]).first
      assert_equal :upcoming, future_balance[:status]
      refute future_balance[:current]
    end
  end

  test "groups several cycles with one pass and keeps zero cycles" do
    income(2_000_000, date: Date.new(2026, 10, 21))
    income(1_000_000, date: Date.new(2026, 9, 21))
    expense(500_000, date: Date.new(2026, 9, 22))

    previous = PayCycle.containing(@user, Date.new(2026, 9, 25))
    data = balances([ previous, @cycle ])

    assert_equal [ 1_000_000.to_d, 2_000_000.to_d ], data.map { |row| row[:income_total] }
    assert_equal [ 500_000.to_d, 0.to_d ], data.map { |row| row[:expense_total] }
  end
end
