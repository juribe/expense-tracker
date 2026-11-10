# frozen_string_literal: true

require "test_helper"

class ReportsCycleTransactionsQueryTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Cycle Query", email: "cycle_query_test@example.com", password: "password123")
    @user.update!(financial_cycle_start_day: 20)
    @income_category = Category.create!(name: "Salario", is_default: true, category_type: "income")
    @expense_category = Category.create!(name: "Domicilios y antojos", is_default: true, category_type: "expense")
    @other_category = Category.create!(name: "Mercado", is_default: true, category_type: "expense")
    @bank = @user.money_sources.create!(name: "Banco", kind: "account", active: true, starting_balance: 100_000_000)
    @card = @user.money_sources.create!(name: "Visa", kind: "credit_card", active: true)
    @card.create_credit_account!(credit_limit: 50_000_000)
    @cycle = PayCycle.containing(@user, Date.new(2026, 10, 25))
    @range = @cycle.to_range
  end

  def income(description, date: Date.new(2026, 10, 21))
    Income.create!(user: @user, category: @income_category, money_source: @bank, amount: 2_000_000,
                   date: date, description: description, source: "manual")
  end

  def expense(description, amount: 100_000, date: Date.new(2026, 10, 22), category: @expense_category)
    Expense.create!(user: @user, category: category, money_source: @bank, amount: -amount.to_d,
                    date: date, description: description, source: "manual")
  end

  def query(**options)
    Reports::CycleTransactionsQuery.new(user: @user, range: @range, **options).call
  end

  test "returns only the cycle real movements in date order" do
    income("Pago de nómina", date: Date.new(2026, 10, 20))
    expense("DiDi CO Food", amount: 44_980, date: Date.new(2026, 10, 24))
    expense("Ciclo anterior", date: Date.new(2026, 10, 19))
    debt_expense = expense("Pago tarjeta", amount: 500_000, date: Date.new(2026, 10, 23), category: @other_category)
    Payment.create!(user: @user, expense: debt_expense, money_source: @card, amount: 500_000,
                    principal_amount: 500_000)
    Transfer.create!(user: @user, from_source: @bank, to_source: @card, amount: 500_000,
                     date: Date.new(2026, 10, 23))

    descriptions = query.map(&:description)

    assert_equal [ "DiDi CO Food", "Pago de nómina" ], descriptions
  end

  test "filters by movement type" do
    income("Pago de nómina")
    expense("DiDi CO Food")

    assert_equal [ "DiDi CO Food" ], query(type: "expense").map(&:description)
    assert_equal [ "Pago de nómina" ], query(type: "income").map(&:description)
    assert_equal 2, query(type: "all").count
    assert_equal 2, query(type: "unknown").count
  end

  test "filters by category" do
    expense("DiDi CO Food", category: @expense_category)
    expense("Mercado central", category: @other_category)

    assert_equal [ "DiDi CO Food" ], query(category_id: @expense_category.id).map(&:description)
  end

  test "ignores a category that does not belong to the user" do
    other = User.create!(name: "Other", email: "cycle_query_other@example.com", password: "password123")
    foreign_category = Category.create!(user: other, name: "Ajena", category_type: "expense", is_default: false)
    expense("DiDi CO Food")

    assert_equal [ "DiDi CO Food" ], query(category_id: foreign_category.id).map(&:description)
  end

  test "searches descriptions case insensitively" do
    expense("DiDi CO Food")
    expense("Mercado central", category: @other_category)

    assert_equal [ "DiDi CO Food" ], query(query: "didi").map(&:description)
    assert_equal [ "Mercado central" ], query(query: "MERCADO").map(&:description)
  end

  test "combines type category and search filters" do
    expense("DiDi CO Food", category: @expense_category)
    expense("DiDi mercado", category: @other_category)
    income("DiDi nómina")

    results = query(type: "expense", category_id: @expense_category.id, query: "DiDi")

    assert_equal [ "DiDi CO Food" ], results.map(&:description)
  end

  test "isolates transactions by user" do
    other = User.create!(name: "Other", email: "cycle_query_isolation@example.com", password: "password123")
    other_bank = other.money_sources.create!(name: "Banco otro", kind: "account", active: true, starting_balance: 1_000_000)
    Expense.create!(user: other, category: @expense_category, money_source: other_bank, amount: -100_000,
                    date: Date.new(2026, 10, 22), description: "Ajena", source: "manual")
    expense("Propia")

    assert_equal [ "Propia" ], query.map(&:description)
  end
end
