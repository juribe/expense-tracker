# frozen_string_literal: true

require "test_helper"

# Payments::BalanceEffect moves only the principal component of a payment
# against the debt balance — never the payment total — and auto-increments
# installments_paid for loan targets. Editing/deleting a payment reverses
# its previous effect first.
#   Payments::BalanceEffect.play!(payment, previous_principal: 900_000)
class BalanceEffectTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Balance User", email: "balance@example.com", password: "password123")
    @account = create_source(kind: "account", name: "Cuenta")
    @mortgage = create_source(kind: "loan", sub_kind: "mortgage", name: "Hipotecario")
    @mortgage.create_credit_account!(principal_amount: 50_000_000, outstanding_balance: 30_000_000,
                                     installment_count: 36)
  end

  test "only principal reduces a loan's outstanding balance" do
    expense = create_expense(amount: 1_500_000, money_source: @account)

    payment = create_payment(expense, @mortgage,
                             principal_amount: 900_000, interest_amount: 400_000,
                             insurance_amount: 150_000, other_amount: 50_000)

    assert_equal BigDecimal("29_100_000"), @mortgage.reload.credit_account.outstanding_balance.to_d
  end

  test "applying a loan payment auto-increments installments_paid" do
    expense = create_expense(amount: 1_500_000, money_source: @account)

    create_payment(expense, @mortgage, principal_amount: 900_000, interest_amount: 600_000)

    assert_equal 1, @mortgage.credit_account.installments_paid
  end

  test "an interest-only loan payment does NOT count as an installment" do
    expense = create_expense(amount: 1_500_000, money_source: @account)

    create_payment(expense, @mortgage, principal_amount: 0, interest_amount: 1_500_000)

    assert_equal 0, @mortgage.credit_account.reload.installments_paid.to_i
  end

  test "promoting an interest-only payment to a real principal payment counts one installment" do
    expense = create_expense(amount: 1_500_000, money_source: @account)
    payment = create_payment(expense, @mortgage, principal_amount: 0, interest_amount: 1_500_000)

    payment.update!(principal_amount: 1_500_000, interest_amount: 0)

    assert_equal 1, @mortgage.credit_account.reload.installments_paid.to_i
  end

  test "demoting a payment to interest-only on edit removes the installment count" do
    expense = create_expense(amount: 1_500_000, money_source: @account)
    payment = create_payment(expense, @mortgage, principal_amount: 900_000, interest_amount: 600_000)

    payment.update!(principal_amount: 0, interest_amount: 1_500_000)

    assert_equal 0, @mortgage.credit_account.reload.installments_paid.to_i
  end

  test "credit card debt is reduced by the principal component only" do
    card = create_source(kind: "credit_card", name: "Tarjeta", starting_balance: -500_000)
    expense = create_expense(amount: 900_000, money_source: @account)

    create_payment(expense, card, principal_amount: 400_000, interest_amount: 500_000)

    assert_equal BigDecimal("-100_000"), card.reload.balance
    assert_equal BigDecimal("100_000"), card.used_credit
  end

  test "payment on a card paid from that same card does not double-move the cash balance" do
    card = create_source(kind: "credit_card", name: "Tarjeta", starting_balance: -500_000)
    expense = create_expense(amount: 500_000, money_source: card)

    assert_equal BigDecimal("-1_000_000"), card.reload.balance

    create_payment(expense, card, principal_amount: 500_000)

    # The expense already moved the card's balance; the payment must not move it again.
    assert_equal BigDecimal("-1_000_000"), card.reload.balance
  end

  test "editing a payment reverses the previous principal and applies the new one" do
    expense = create_expense(amount: 1_500_000, money_source: @account)
    payment = create_payment(expense, @mortgage, principal_amount: 900_000, interest_amount: 600_000)

    payment.update!(principal_amount: 850_000, interest_amount: 650_000)

    assert_equal BigDecimal("29_150_000"), @mortgage.reload.credit_account.outstanding_balance.to_d
  end

  test "destroying a payment restores the previous loan balance and installment count" do
    expense = create_expense(amount: 1_500_000, money_source: @account)
    payment = create_payment(expense, @mortgage, principal_amount: 900_000, interest_amount: 600_000)

    payment.destroy!

    assert_equal BigDecimal("30_000_000"), @mortgage.reload.credit_account.outstanding_balance.to_d
    assert_equal 0, @mortgage.credit_account.installments_paid
  end

  test "destroying a card payment re-releases the principal as available credit" do
    card = create_source(kind: "credit_card", name: "Tarjeta", starting_balance: -500_000)
    expense = create_expense(amount: 900_000, money_source: @account)
    payment = create_payment(expense, card, principal_amount: 400_000, interest_amount: 500_000)

    payment.destroy!

    assert_equal BigDecimal("-500_000"), card.reload.balance
  end

  test "destroying an interest-only payment never touches the installment count" do
    expense = create_expense(amount: 1_500_000, money_source: @account)
    payment = create_payment(expense, @mortgage, principal_amount: 0, interest_amount: 1_500_000)

    payment.destroy!

    assert_equal 0, @mortgage.reload.credit_account.installments_paid.to_i
  end

  test "an unknown distribution never touches the balance" do
    expense = create_expense(amount: 1_500_000, money_source: @account)

    create_payment(expense, @mortgage, principal_amount: 0, interest_amount: 1_500_000)

    assert_equal BigDecimal("30_000_000"), @mortgage.reload.credit_account.outstanding_balance.to_d
    assert_equal 0, @mortgage.credit_account.installments_paid.to_i
  end

  test "principal larger than the outstanding balance clamps to zero" do
    expense = create_expense(amount: 1_500_000, money_source: @account)
    small_loan = create_source(kind: "loan", sub_kind: "vehicle", name: "Casi pagado")
    small_loan.create_credit_account!(principal_amount: 10_000_000, outstanding_balance: 1_000_000)

    create_payment(expense, small_loan, principal_amount: 1_500_000)

    assert_equal BigDecimal("0"), small_loan.reload.credit_account.outstanding_balance.to_d
  end

  # A revolving line has no schedule: payments lower the debt but never fake
  # installment progress either way.
  test "a principal payment on a revolving loan never counts an installment" do
    revolving = create_source(kind: "loan", sub_kind: "revolving", name: "Rotativo")
    revolving.create_credit_account!(principal_amount: 50_000_000, outstanding_balance: 8_000_000,
                                     installment_amount: 400_000, installment_count: 36)
    expense = create_expense(amount: 2_000_000, money_source: @account)

    create_payment(expense, revolving, principal_amount: 2_000_000)

    assert_equal BigDecimal("6_000_000"), revolving.reload.credit_account.outstanding_balance.to_d
    assert_equal 0, revolving.credit_account.installments_paid.to_i
  end

  test "destroying a revolving payment restores the balance and never un-counts installments" do
    revolving = create_source(kind: "loan", sub_kind: "revolving", name: "Rotativo")
    revolving.create_credit_account!(principal_amount: 50_000_000, outstanding_balance: 8_000_000,
                                     installment_amount: 400_000, installment_count: 36)
    expense = create_expense(amount: 2_000_000, money_source: @account)
    payment = create_payment(expense, revolving, principal_amount: 2_000_000)

    payment.destroy!

    assert_equal BigDecimal("8_000_000"), revolving.reload.credit_account.outstanding_balance.to_d
    assert_equal 0, revolving.credit_account.installments_paid.to_i
  end

  private

  def create_source(kind:, name:, sub_kind: nil, starting_balance: 100_000)
    @user.money_sources.create!(name: name, kind: kind, sub_kind: sub_kind, starting_balance: starting_balance)
  end

  def create_expense(amount:, money_source:)
    Expense.create!(
      user: @user, amount: amount, description: "Payment",
      date: Date.current, kind: "expense", source: "manual", money_source: money_source
    )
  end

  def create_payment(expense, target, principal_amount:, interest_amount: 0, insurance_amount: 0, other_amount: 0)
    # Reload the loan's credit account so callbacks see fresh balances.
    target.credit_account.reload if target.loan?
    Payment.create!(
      user: @user, expense: expense, money_source: target, date: expense.date,
      amount: principal_amount + interest_amount + insurance_amount + other_amount,
      principal_amount: principal_amount, interest_amount: interest_amount,
      insurance_amount: insurance_amount, other_amount: other_amount
    )
  end
end
