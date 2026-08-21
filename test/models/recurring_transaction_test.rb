# frozen_string_literal: true

require "test_helper"

class RecurringTransactionTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "RT User", email: "rt_model@example.com", password: "password123")
    @category = Category.create!(name: "Salary Model")
  end

  test "is valid with required attributes" do
    rt = RecurringTransaction.new(
      user: @user,
      category: @category,
      transaction_type: "income",
      amount: 6500,
      description: "Freelance Job",
      payment_day: 15
    )

    assert rt.valid?
    assert_equal "monthly", rt.frequency
    assert rt.active?
  end

  test "requires a user, category, amount and payment day" do
    rt = RecurringTransaction.new
    refute rt.valid?
    assert_not_empty rt.errors[:user]
    assert_not_empty rt.errors[:category]
    assert_not_empty rt.errors[:amount]
    assert_not_empty rt.errors[:payment_day]
  end

  test "rejects non-positive amounts" do
    rt = build_recurring_transaction(amount: 0)
    refute rt.valid?
    assert_not_empty rt.errors[:amount]

    rt.amount = -10
    refute rt.valid?
  end

  test "restricts payment day between 1 and 31" do
    refute build_recurring_transaction(payment_day: 0).valid?
    refute build_recurring_transaction(payment_day: 32).valid?
    assert build_recurring_transaction(payment_day: 1).valid?
    assert build_recurring_transaction(payment_day: 31).valid?
  end

  test "only accepts income or expense transaction types" do
    rt = build_recurring_transaction(transaction_type: "transfer")
    refute rt.valid?
    assert_not_empty rt.errors[:transaction_type]
  end

  test "action_label is Receive for income and Pay for expense" do
    assert_equal "Receive", build_recurring_transaction(transaction_type: "income").action_label
    assert_equal "Pay", build_recurring_transaction(transaction_type: "expense").action_label
  end

  test "completed_action_label uses proper past tense" do
    assert_equal "Received", build_recurring_transaction(transaction_type: "income").completed_action_label
    assert_equal "Paid", build_recurring_transaction(transaction_type: "expense").completed_action_label
  end

  test "status_for reports pending, completed and inactive" do
    rt = RecurringTransaction.create!(
      user: @user,
      category: @category,
      transaction_type: "income",
      amount: 100,
      payment_day: 5
    )
    period = Date.current.strftime("%Y-%m")

    assert_equal :pending, rt.status_for(period)

    RecurringTransactionProcessor.call(recurring_transaction: rt, amount: 100, date: Date.current)

    assert_equal :completed, rt.status_for(period)

    rt.update!(active: false)
    assert_equal :inactive, rt.status_for(period)
  end

  test "of_type and ordered scopes behave" do
    income = RecurringTransaction.create!(
      user: @user, category: @category, transaction_type: "income",
      amount: 100, payment_day: 20
    )
    expense = RecurringTransaction.create!(
      user: @user, category: @category, transaction_type: "expense",
      amount: 200, payment_day: 10
    )

    assert_equal [income], @user.recurring_transactions.of_type("income").to_a
    assert_equal [ expense, income ], @user.recurring_transactions.ordered.to_a
  end

  private

  def build_recurring_transaction(overrides = {})
    RecurringTransaction.new(
      {
        user: @user,
        category: @category,
        transaction_type: "income",
        amount: 100,
        payment_day: 15
      }.merge(overrides)
    )
  end
end
