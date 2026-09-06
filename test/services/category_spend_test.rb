# frozen_string_literal: true

require "test_helper"

class CategorySpendTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      name: "Spend User",
      email: "category_spend_test@example.com",
      password: "password123"
    )
    @category = Category.create!(
      name: "Mercado_#{SecureRandom.hex(4)}",
      category_type: "expense",
      user: @user
    )
    @month = Date.current
  end

  def create_expense(amount, date: @month, category: @category, user: @user)
    Expense.create!(user: user, category: category, amount: amount, date: date, description: "test")
  end

  test "sums expenses for the user, category and month as a positive value" do
    create_expense(300_000)
    create_expense(200_000, date: @month.end_of_month)
    create_expense(50_000, date: @month.beginning_of_month)

    assert_equal 550_000.to_d, CategorySpend.call(user: @user, category: @category, month: @month)
  end

  test "ignores expenses of other months" do
    create_expense(300_000)
    create_expense(999_999, date: @month.prev_month)
    create_expense(999_999, date: @month.next_month)

    assert_equal 300_000.to_d, CategorySpend.call(user: @user, category: @category, month: @month)
  end

  test "ignores expenses of other users and categories" do
    other_user = User.create!(name: "Other", email: "spend_other_#{SecureRandom.hex(4)}@example.com", password: "password123")
    other_category = Category.create!(name: "Otro_#{SecureRandom.hex(4)}", category_type: "expense", user: @user)

    create_expense(100_000)
    create_expense(777_777, user: other_user)
    create_expense(888_888, category: other_category)

    assert_equal 100_000.to_d, CategorySpend.call(user: @user, category: @category, month: @month)
  end

  test "ignores income transactions" do
    Transaction.create!(user: @user, category: @category, amount: 500_000, date: @month, kind: "income", source: "test")

    assert_equal 0.to_d, CategorySpend.call(user: @user, category: @category, month: @month)
  end

  test "returns zero when there is no spending" do
    assert_equal 0.to_d, CategorySpend.call(user: @user, category: @category, month: @month)
  end
end
