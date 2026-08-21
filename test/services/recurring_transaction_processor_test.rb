# frozen_string_literal: true

require "test_helper"

class RecurringTransactionProcessorTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Proc User", email: "processor@example.com", password: "password123")
    @category = Category.create!(name: "Salary Proc")
    @recurring = RecurringTransaction.create!(
      user: @user,
      category: @category,
      transaction_type: "income",
      amount: 6500,
      description: "Freelance Income",
      payment_day: 15
    )
    @date = Date.new(2026, 8, 18)
  end

  test "processing income creates a one_time Income and an occurrence" do
    result = RecurringTransactionProcessor.call(
      recurring_transaction: @recurring,
      amount: 6500,
      date: @date
    )

    assert result.success?, result.error

    income = result.transaction
    assert_equal "Income", income.class.name
    assert_equal @user.id, income.user_id
    assert_equal @category.id, income.category_id
    assert_equal BigDecimal("6500"), income.amount
    assert_equal "Freelance Income", income.description
    assert_equal @date, income.date
    assert_equal "one_time", income.frequency

    occurrence = result.occurrence
    assert_equal @recurring.id, occurrence.recurring_transaction_id
    assert_equal income.id, occurrence.transaction_id
    assert_equal "Income", occurrence.transaction_type
    assert_equal @date, occurrence.transaction_date
    assert_equal "2026-08", occurrence.period
  end

  test "processing expense creates a one_time Expense" do
    @recurring.update!(transaction_type: "expense")

    result = RecurringTransactionProcessor.call(
      recurring_transaction: @recurring,
      amount: "2817600.50",
      date: @date
    )

    assert result.success?, result.error
    assert_equal "Expense", result.transaction.class.name
    assert_equal BigDecimal("2817600.5"), result.transaction.amount
    assert_equal "one_time", result.transaction.frequency
  end

  test "recurring configuration stays active after processing" do
    RecurringTransactionProcessor.call(recurring_transaction: @recurring, amount: 6500, date: @date)

    assert @recurring.reload.active?
  end

  test "duplicate processing for the same month is rejected" do
    RecurringTransactionProcessor.call(recurring_transaction: @recurring, amount: 6500, date: @date)

    result = RecurringTransactionProcessor.call(
      recurring_transaction: @recurring,
      amount: 6500,
      date: Date.new(2026, 8, 25)
    )

    refute result.success?
    assert_match(/Already processed/i, result.error)
    assert_equal 1, @recurring.occurrences.count
    assert_equal 1, Income.where(user: @user).count
  end

  test "processing in a later month is allowed" do
    RecurringTransactionProcessor.call(recurring_transaction: @recurring, amount: 6500, date: @date)

    result = RecurringTransactionProcessor.call(
      recurring_transaction: @recurring,
      amount: 6800,
      date: Date.new(2026, 9, 15)
    )

    assert result.success?, result.error
    assert_equal "2026-09", result.occurrence.period
    assert_equal 2, @recurring.occurrences.count
  end

  test "rejects inactive recurring transactions" do
    @recurring.update!(active: false)

    result = RecurringTransactionProcessor.call(recurring_transaction: @recurring, amount: 100, date: @date)

    refute result.success?
    assert_match(/inactive/i, result.error)
    assert_empty Income.where(user: @user)
  end

  test "rejects non-positive amounts and invalid dates" do
    refute RecurringTransactionProcessor.call(
      recurring_transaction: @recurring, amount: 0, date: @date
    ).success?

    refute RecurringTransactionProcessor.call(
      recurring_transaction: @recurring, amount: -5, date: @date
    ).success?

    refute RecurringTransactionProcessor.call(
      recurring_transaction: @recurring, amount: 10, date: "not-a-date"
    ).success?

    assert_empty Income.where(user: @user)
  end

  test "rolls back both records when the occurrence cannot be saved" do
    # A DB-level guard makes the occurrence INSERT fail right after the Income
    # was created; the surrounding transaction must roll both back.
    connection = ActiveRecord::Base.connection
    connection.execute(<<~SQL)
      CREATE TRIGGER force_occurrence_failure
      BEFORE INSERT ON recurring_transaction_occurrences
      FOR EACH ROW
      WHEN NEW.period = '2099-01'
      BEGIN
        SELECT RAISE(ABORT, 'forced failure');
      END;
    SQL

    assert_raises ActiveRecord::StatementInvalid do
      RecurringTransactionProcessor.call(
        recurring_transaction: @recurring,
        amount: 100,
        date: Date.new(2099, 1, 15)
      )
    end

    connection.execute("DROP TRIGGER force_occurrence_failure")

    assert_empty Income.where(user: @user)
    assert_empty @recurring.occurrences
  end
end
