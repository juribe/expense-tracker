# frozen_string_literal: true

require "test_helper"

# Payment: the accounting application of an existing Expense to a debt
# (credit card or loan). Not a new cash movement — the Expense is.
#   Payment.create!(expense:, money_source:, amount:, principal_amount:, ...)
class PaymentTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Payments User", email: "payments@example.com", password: "password123")
    @account = create_source(kind: "account", name: "Cuenta Davibank")
    @card = create_source(kind: "credit_card", name: "Tarjeta Davibank")
    @mortgage = create_source(kind: "loan", sub_kind: "mortgage", name: "Hipotecario")
  end

  test "applies an existing expense to debt without creating another expense" do
    @mortgage.create_credit_account!(principal_amount: 50_000_000, outstanding_balance: 30_000_000)
    expense = create_expense(amount: 1_500_000, description: "Mortgage payment", money_source: @account)

    payment = Payment.create!(
      user: @user,
      expense: expense,
      money_source: @mortgage,
      date: expense.date,
      amount: 1_500_000,
      principal_amount: 900_000,
      interest_amount: 400_000,
      insurance_amount: 150_000,
      other_amount: 50_000
    )

    assert payment.persisted?
    assert_equal expense.id, payment.expense_id
    assert_equal 1, Expense.count
    assert_predicate payment.expense, :expense?
  end

  test "components must sum to the payment amount" do
    expense = create_expense(amount: 1_500_000, money_source: @account)

    payment = Payment.new(
      user: @user, expense: expense, money_source: @mortgage, date: expense.date,
      amount: 1_500_000, principal_amount: 900_000, interest_amount: 400_000,
      insurance_amount: 150_000, other_amount: 49_000
    )

    assert_not payment.valid?
    assert payment.errors[:base].present?
  end

  test "payment amount must equal the expense amount" do
    expense = create_expense(amount: 1_500_000, money_source: @account)

    payment = Payment.new(
      user: @user, expense: expense, money_source: @mortgage, date: expense.date,
      amount: 1_000_000, principal_amount: 1_000_000
    )

    assert_not payment.valid?
    assert payment.errors[:amount].present?
  end

  test "components must be positive or zero and amount greater than zero" do
    expense = create_expense(amount: 500_000, money_source: @account)

    negative = Payment.new(
      user: @user, expense: expense, money_source: @mortgage, date: expense.date,
      amount: 500_000, principal_amount: 600_000, interest_amount: -100_000
    )
    assert_not negative.valid?

    zero = Payment.new(
      user: @user, expense: expense, money_source: @mortgage, date: expense.date,
      amount: 0, principal_amount: 0
    )
    assert_not zero.valid?
  end

  test "target must be a debt payment target" do
    expense = create_expense(amount: 500_000, money_source: @account)

    payment = Payment.new(
      user: @user, expense: expense, money_source: @account, date: expense.date,
      amount: 500_000, principal_amount: 500_000
    )

    assert_not payment.valid?
    assert payment.errors[:money_source].present?
  end

  test "expense and target must belong to the payment user" do
    other_user = User.create!(name: "Other", email: "other-pay@example.com", password: "password123")
    other_expense = Expense.create!(
      user: other_user, amount: 500_000, description: "Pago ajeno",
      date: Date.current, kind: "expense", source: "manual"
    )

    payment = Payment.new(
      user: @user, expense: other_expense, money_source: @mortgage, date: other_expense.date,
      amount: 500_000, principal_amount: 500_000
    )

    assert_not payment.valid?
    assert payment.errors[:expense].present?

    other_source = other_user.money_sources.create!(name: "Ajena", kind: "loan", sub_kind: "vehicle", starting_balance: 0)
    my_expense = create_expense(amount: 500_000, money_source: @account)
    foreign_target = Payment.new(
      user: @user, expense: my_expense, money_source: other_source, date: my_expense.date,
      amount: 500_000, principal_amount: 500_000
    )
    assert_not foreign_target.valid?
    assert foreign_target.errors[:money_source].present?
  end

  test "an expense cannot be applied twice to the same debt" do
    expense = create_expense(amount: 600_000, money_source: @account)
    payment_distribution = {
      date: expense.date, amount: 600_000, principal_amount: 600_000
    }.merge(expense: expense, money_source: @mortgage, user: @user)

    Payment.create!(payment_distribution)

    assert_raises ActiveRecord::RecordNotUnique do
      Payment.create!(payment_distribution)
    end
  end

  test "the same expense CAN be applied to two different debts" do
    vehicle = create_source(kind: "loan", sub_kind: "vehicle", name: "Crédito Vehículo")
    expense = create_expense(amount: 600_000, money_source: @account)

    first = Payment.create!(
      user: @user, expense: expense, money_source: @mortgage, date: expense.date,
      amount: 600_000, principal_amount: 600_000
    )
    second = Payment.create!(
      user: @user, expense: expense, money_source: vehicle, date: expense.date,
      amount: 600_000, principal_amount: 600_000
    )

    assert first.persisted?
    assert second.persisted?
  end

  test "distribution_total is the sum of the components" do
    expense = create_expense(amount: 1_500_000, money_source: @account)
    payment = Payment.new(
      user: @user, expense: expense, money_source: @mortgage, date: expense.date,
      amount: 1_500_000, principal_amount: 900_000, interest_amount: 400_000,
      insurance_amount: 150_000, other_amount: 50_000
    )

    assert_equal BigDecimal("1500000"), payment.distribution_total
  end

  test "accepts shadowed interest-only distribution matching the expense amount" do
    expense = create_expense(amount: 800_000, money_source: @account)

    payment = Payment.new(
      user: @user, expense: expense, money_source: @mortgage, date: expense.date,
      amount: 800_000, principal_amount: 0, interest_amount: 800_000
    )

    assert payment.valid?
  end

  test "date defaults to the expense date" do
    expense = create_expense(amount: 500_000, money_source: @account)

    payment = Payment.new(
      user: @user, expense: expense, money_source: @mortgage,
      amount: 500_000, principal_amount: 500_000
    )

    assert_equal expense.date, payment.date
  end

  private

  def create_source(kind:, name:, sub_kind: nil)
    @user.money_sources.create!(name: name, kind: kind, sub_kind: sub_kind, starting_balance: 100_000)
  end

  def create_expense(amount:, description: "Payment", money_source: nil)
    Expense.create!(
      user: @user, amount: amount, description: description,
      date: Date.current, kind: "expense", source: "manual", money_source: money_source
    )
  end
end
