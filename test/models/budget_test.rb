# frozen_string_literal: true

require "test_helper"

class BudgetTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      name: "Budget User",
      email: "budget_test@example.com",
      password: "password123"
    )
    @category = Category.create!(
      name: "Compras_#{SecureRandom.hex(4)}",
      category_type: "expense",
      user: @user
    )
  end

  test "is valid with a positive monthly amount" do
    budget = Budget.new(user: @user, category: @category, monthly_amount: 1_000_000, period: "monthly", active: true)
    assert budget.valid?
  end

  test "requires a positive monthly amount" do
    budget = Budget.new(user: @user, category: @category, monthly_amount: 0, period: "monthly", active: true)
    assert_not budget.valid?
    assert budget.errors[:monthly_amount].any?
  end

  test "requires user and category" do
    budget = Budget.new(monthly_amount: 1_000_000, period: "monthly", active: true)
    assert_not budget.valid?
    assert budget.errors[:user].any?
    assert budget.errors[:category].any?
  end

  test "destroying the category removes its budgets" do
    budget = Budget.create!(user: @user, category: @category, monthly_amount: 1_000_000, period: "monthly", active: true)
    @category.destroy!
    assert_not Budget.exists?(budget.id)
  end
end
