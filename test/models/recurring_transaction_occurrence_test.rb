# frozen_string_literal: true

require "test_helper"

class RecurringTransactionOccurrenceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Occ User", email: "occurrence@example.com", password: "password123")
    @category = Category.create!(name: "Rental Occ")
    @recurring = RecurringTransaction.create!(
      user: @user,
      category: @category,
      transaction_type: "income",
      amount: 1200,
      payment_day: 1
    )
  end

  test "links to the generated transaction polymorphically" do
    income = Income.create!(
      user: @user,
      category: @category,
      amount: 1200,
      date: Date.new(2026, 8, 18),
      frequency: "one_time"
    )

    occurrence = RecurringTransactionOccurrence.create!(
      recurring_transaction: @recurring,
      generated_transaction: income,
      transaction_date: Date.new(2026, 8, 18),
      period: "2026-08"
    )

    assert_equal income, occurrence.generated_transaction
    assert_equal "Income", occurrence.transaction_type
    assert_equal income.id, occurrence.transaction_id
  end

  test "requires a date in YYYY-MM period format" do
    occurrence = RecurringTransactionOccurrence.new(
      recurring_transaction: @recurring,
      generated_transaction: build_income,
      transaction_date: Date.current,
      period: "August 2026"
    )

    refute occurrence.valid?
    assert_not_empty occurrence.errors[:period]
  end

  test "prevents duplicate periods for the same recurring transaction" do
    RecurringTransactionOccurrence.create!(
      recurring_transaction: @recurring,
      generated_transaction: create_income(Date.new(2026, 8, 15)),
      transaction_date: Date.new(2026, 8, 15),
      period: "2026-08"
    )

    duplicate = RecurringTransactionOccurrence.new(
      recurring_transaction: @recurring,
      generated_transaction: build_income,
      transaction_date: Date.new(2026, 8, 20),
      period: "2026-08"
    )

    refute duplicate.valid?
    assert_not_empty duplicate.errors[:period]
  end

  test "allows the same period for different recurring transactions" do
    other_user = User.create!(name: "Other Occ", email: "other-occ@example.com", password: "password123")
    other_recurring = RecurringTransaction.create!(
      user: other_user,
      category: @category,
      transaction_type: "expense",
      amount: 300,
      payment_day: 2
    )

    RecurringTransactionOccurrence.create!(
      recurring_transaction: @recurring,
      generated_transaction: create_income(Date.new(2026, 8, 1)),
      transaction_date: Date.new(2026, 8, 1),
      period: "2026-08"
    )

    assert_nothing_raised do
      RecurringTransactionOccurrence.create!(
        recurring_transaction: other_recurring,
        generated_transaction: create_expense(other_user, Date.new(2026, 8, 2)),
        transaction_date: Date.new(2026, 8, 2),
        period: "2026-08"
      )
    end
  end

  private

  def build_income
    Income.new(user: @user, category: @category, amount: 100, date: Date.current, frequency: "one_time")
  end

  def create_income(date)
    Income.create!(user: @user, category: @category, amount: 100, date: date, frequency: "one_time")
  end

  def create_expense(user, date)
    Expense.create!(user: user, category: @category, amount: 50, date: date, frequency: "one_time")
  end
end
