require "test_helper"

class FinancialHabitsAnalysisTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Habits User", email: "habits_#{SecureRandom.hex(4)}@example.com", password: "password123")
    @category = Category.where(category_type: "expense").first
    @income_category = Category.where(category_type: "income").first
    @bank = @user.money_sources.create!(name: "Cuenta", kind: "account", active: true, starting_balance: 10_000_000)
  end

  def expense(amount, date: Date.current, description: "Gasto", category: @category, source: @bank)
    Expense.create!(user: @user, category: category, money_source: source, amount: amount, date: date, description: description)
  end

  def income(amount, date: Date.current, description: "Salario")
    Income.create!(user: @user, category: @income_category, money_source: @bank, amount: amount, date: date, description: description)
  end

  test "returns empty state without movements" do
    result = FinancialHabits::Analysis.new(user: @user).call

    assert_equal :empty, result[:state]
    assert_empty result[:discoveries]
  end

  test "detects income spending pattern" do
    income(5_000_000, date: Date.current.beginning_of_month)
    8.times { |i| expense(-100_000, date: Date.current.beginning_of_month + (i % 4).days, description: "Comida") }

    result = FinancialHabits::Analysis.new(user: @user).call

    assert_includes result[:discoveries].map { |item| item[:key] }, "income_spending_pattern"
  end

  test "detects recurring merchants" do
    4.times { |i| expense(-12_000, date: Date.current.beginning_of_month + i.days, description: "Café") }

    result = FinancialHabits::Analysis.new(user: @user).call

    assert_includes result[:discoveries].map { |item| item[:key] }, "merchant_frequency"
  end
end