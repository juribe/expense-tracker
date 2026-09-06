# frozen_string_literal: true

require "test_helper"

class BudgetTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Test User", email: "budget_test@example.com", password: "password123")
    @category = Category.create!(name: "Restaurants", is_default: true, category_type: "expense")
    @month = Date.new(2026, 9, 1)
  end

  def create_budget(**overrides)
    Budget.create!(
      { user: @user, category: @category, monthly_amount: 800_000, period: "monthly" }.merge(overrides)
    )
  end

  def create_expense(amount:, date:, category: @category)
    Expense.create!(user: @user, category: category, amount: amount, date: date, description: "Test")
  end

  test "is valid with required attributes" do
    budget = Budget.new(user: @user, category: @category, monthly_amount: 100_000)
    assert budget.valid?
  end

  test "monthly_amount is required and must be positive" do
    budget = Budget.new(user: @user, category: @category)
    assert_not budget.valid?
    assert_includes budget.errors[:monthly_amount], I18n.t("errors.messages.blank")

    budget.monthly_amount = 0
    assert_not budget.valid?
    assert_includes budget.errors[:monthly_amount], I18n.t("errors.messages.greater_than", count: 0)
  end

  test "category is required" do
    budget = Budget.new(user: @user, monthly_amount: 100_000)
    assert_not budget.valid?
    assert_includes budget.errors[:category_id], I18n.t("errors.messages.blank")
  end

  test "period defaults to monthly" do
    assert_equal "monthly", create_budget.period
  end

  test "normalizes es-formatted monthly amount on save" do
    budget = Budget.new(user: @user, category: @category, monthly_amount: "800000")
    assert budget.valid?
    assert_equal 800_000, budget.monthly_amount

    budget.monthly_amount = "1.500.000,50"
    assert budget.valid?
    assert_equal 1_500_000.5, budget.monthly_amount

    budget.monthly_amount = "500,5"
    assert budget.valid?
    assert_equal 500.5, budget.monthly_amount

    budget.monthly_amount = 500_000
    assert budget.valid?
    assert_equal 500_000, budget.monthly_amount
  end

  test "keeps machine-formatted decimal monthly amounts" do
    budget = Budget.new(user: @user, category: @category, monthly_amount: "500.5")
    assert budget.valid?
    assert_equal 500.5, budget.monthly_amount
  end

  test "only expense categories can be budgeted" do
    income_category = Category.create!(name: "Salary", is_default: true, category_type: "income")
    budget = Budget.new(user: @user, category: income_category, monthly_amount: 100_000)
    assert_not budget.valid?
    assert_includes budget.errors[:category_id], I18n.t("budgets.validation.expense_type")
  end

  test "category must belong to the user or be a default" do
    other_user = User.create!(name: "Other", email: "budget_other@example.com", password: "password123")
    other_category = Category.create!(name: "Theirs", is_default: false, category_type: "expense", user: other_user)
    budget = Budget.new(user: @user, category: other_category, monthly_amount: 100_000)
    assert_not budget.valid?
    assert_includes budget.errors[:category_id], I18n.t("budgets.validation.invalid_category")
  end

  test "user can only have one budget per category" do
    create_budget
    duplicate = Budget.new(user: @user, category: @category, monthly_amount: 50_000)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:category_id], I18n.t("errors.messages.taken")
  end

  test "user can have budgets for different categories" do
    other_category = Category.create!(name: "Transport", is_default: true, category_type: "expense")
    create_budget
    assert Budget.new(user: @user, category: other_category, monthly_amount: 50_000).valid?
  end

  test "spending calculation sums absolute amount of category expenses in the month" do
    budget = create_budget(monthly_amount: 800_000)
    create_expense(amount: 200_000, date: @month)
    create_expense(amount: 100_000, date: @month + 5.days)
    create_expense(amount: 50_000, date: @month.beginning_of_month + 10.days)

    assert_equal 350_000, budget.spent_for(@month)
  end

  test "spent_for ignores expenses from other categories" do
    budget = create_budget
    other_category = Category.create!(name: "Shopping", is_default: true, category_type: "expense")
    create_expense(amount: 300_000, date: @month)
    create_expense(amount: 900_000, date: @month, category: other_category)

    assert_equal 300_000, budget.spent_for(@month)
  end

  test "spent_for ignores expenses from other users" do
    budget = create_budget
    other_user = User.create!(name: "Other", email: "budget_spent_other@example.com", password: "password123")
    Expense.create!(user: other_user, category: @category, amount: 900_000, date: @month)

    assert_equal 0, budget.spent_for(@month)
  end

  test "remaining is monthly amount minus spent" do
    budget = create_budget(monthly_amount: 800_000)
    create_expense(amount: 620_000, date: @month)

    assert_equal 180_000, budget.remaining_for(@month)
  end

  test "remaining is negative when over budget" do
    budget = create_budget(monthly_amount: 800_000)
    create_expense(amount: 900_000, date: @month)

    assert_equal(-100_000, budget.remaining_for(@month))
  end

  test "percentage is spent divided by monthly amount" do
    budget = create_budget(monthly_amount: 800_000)
    create_expense(amount: 620_000, date: @month)

    assert_in_delta 77.5, budget.percentage_for(@month), 0.001
  end

  test "percentage is zero when there are no expenses" do
    budget = create_budget(monthly_amount: 800_000)
    assert_equal 0.0, budget.percentage_for(@month)
  end

  test "on track when below near-limit threshold" do
    budget = create_budget(monthly_amount: 100_000)
    create_expense(amount: 62_000, date: @month)

    assert_equal :on_track, budget.status_for(@month)
    assert budget.on_track?(@month)
    assert_not budget.near_limit?(@month)
    assert_not budget.over_budget?(@month)
  end

  test "near limit at 80% usage" do
    budget = create_budget(monthly_amount: 100_000)
    create_expense(amount: 80_000, date: @month)

    assert_equal :near_limit, budget.status_for(@month)
    assert budget.near_limit?(@month)
    assert_not budget.over_budget?(@month)
  end

  test "near limit when spending up to 100% of the budget" do
    budget = create_budget(monthly_amount: 100_000)
    create_expense(amount: 95_000, date: @month)

    assert_equal :near_limit, budget.status_for(@month)
    assert budget.near_limit?(@month)
  end

  test "over budget when spending exceeds 100%" do
    budget = create_budget(monthly_amount: 100_000)
    create_expense(amount: 120_000, date: @month)

    assert_equal :over_budget, budget.status_for(@month)
    assert budget.over_budget?(@month)
    assert_not budget.near_limit?(@month)
  end

  test "spent_for excludes transfers" do
    budget = create_budget(monthly_amount: 100_000)
    create_expense(amount: 40_000, date: @month)

    savings = @user.money_sources.create!(name: "Savings", kind: "account", starting_balance: 100_000)
    checking = @user.money_sources.create!(name: "Checking", kind: "account", starting_balance: 0)
    Transfer.create!(user: @user, from_source: savings, to_source: checking, amount: 30_000, date: @month)

    assert_equal 40_000, budget.spent_for(@month)
  end

  test "correct month boundary: expenses outside the month do not count" do
    budget = create_budget(monthly_amount: 100_000)
    create_expense(amount: 40_000, date: @month)
    create_expense(amount: 50_000, date: @month.prev_month.end_of_month)
    create_expense(amount: 60_000, date: @month.next_month.beginning_of_month)

    assert_equal 40_000, budget.spent_for(@month)
    assert_equal 50_000, budget.spent_for(@month.prev_month)
    assert_equal 60_000, budget.spent_for(@month.next_month)

    assert_equal :on_track, budget.status_for(@month)
  end

  test "active scope returns only active budgets" do
    active = create_budget
    inactive = create_budget(category: Category.create!(name: "Shopping", is_default: true, category_type: "expense"),
                             active: false)
    assert_includes Budget.active, active
    assert_not_includes Budget.active, inactive
  end

  test "for_user scope returns only the user's budgets" do
    mine = create_budget
    other_user = User.create!(name: "Other", email: "budget_scope_other@example.com", password: "password123")
    other_category = Category.create!(name: "Their Cat", is_default: true, category_type: "expense")
    theirs = Budget.create!(user: other_user, category: other_category, monthly_amount: 10_000)

    assert_includes Budget.for_user(@user), mine
    assert_not_includes Budget.for_user(@user), theirs
  end

  test "updating budget changes monthly amount" do
    budget = create_budget(monthly_amount: 100_000)
    budget.update!(monthly_amount: 250_000)
    assert_equal 250_000, budget.reload.monthly_amount
  end

  test "destroys cleanly" do
    budget = create_budget
    assert_difference "Budget.count", -1 do
      budget.destroy
    end
  end

  test "destroying the category destroys its budgets" do
    category = Category.create!(name: "Temporary", is_default: false, category_type: "expense", user: @user)
    create_budget(category: category)
    assert_difference "Budget.count", -1 do
      category.destroy
    end
  end
end
