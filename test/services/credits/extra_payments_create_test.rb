# frozen_string_literal: true

require "test_helper"

# Credits::ExtraPayments::Create records a REAL extraordinary payment: a cash
# Expense leaves the chosen funding source and a Payment is applied to the
# debt (principal-only for reduce strategies; face value for prepay), so the
# loan's balance moves through the standard store machinery.
class ExtraPaymentsCreateTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Extra User", email: "extra@example.com", password: "password123")
    @loan = @user.money_sources.create!(name: "Ref Loan", kind: "loan", sub_kind: "personal")
    @loan.create_credit_account!(
      outstanding_balance: 1_200, interest_rate: 1.0, interest_rate_type: "monthly",
      installment_amount: 300, installment_count: 5, installments_paid: 0,
      start_date: Date.new(2026, 1, 5), payment_frequency: "monthly"
    )
    @account = @user.money_sources.create!(name: "Ahorros", kind: "account", starting_balance: 500_000)
    Credits::Projection::Builder.call(money_source: @loan).result
  end

  test "reduce_term creates a real expense + principal-only payment" do
    result = Credits::ExtraPayments::Create.call(
      money_source: @loan, funding_money_source: @account, date: Date.new(2026, 9, 5),
      amount: "300", application_type: "reduce_term", note: "Aguinaldo"
    )

    assert result.success?
    payment = result.result
    assert_equal BigDecimal("300"), payment.amount
    assert_equal "reduce_term", payment.application_type
    assert_equal BigDecimal("300"), payment.principal_reduction
    assert payment.effect["interest_saved"].present?

    # Real cash left the funding account.
    assert_equal BigDecimal("500_000") - BigDecimal("300"), @account.reload.balance
    assert_equal "expense", payment.expense.kind
    # Real payment: principal-only distribution; the loan's balance moved.
    assert_equal BigDecimal("300"), payment.payment.principal_amount.to_d
    assert_equal BigDecimal("0"), payment.payment.interest_amount.to_d
    assert_equal BigDecimal("900"), @loan.reload.credit_account.outstanding_balance.to_d
    # It becomes part of the loan's own payment list.
    assert_includes @loan.payments.map(&:id), payment.payment.id
  end

  test "prepay carries the covered installments at face value" do
    result = Credits::ExtraPayments::Create.call(
      money_source: @loan, funding_money_source: @account, date: Date.new(2026, 9, 5),
      amount: "900", application_type: "prepay_installments"
    )

    assert result.success?
    payment = result.result
    # Covered 3 installments at face value (rounded to cents): 288.00 +
    # 290.88 + 293.79 of capital and 27.33 of pre-collected interest.
    assert_equal 3, payment.installments_affected
    assert_equal BigDecimal("872.67"), payment.principal_reduction
    assert_equal BigDecimal("900"), payment.amount
    assert_equal BigDecimal("27.33"), payment.payment.interest_amount.to_d
    assert_equal BigDecimal("327.33"),
                 @loan.reload.credit_account.outstanding_balance.to_d
  end

  test "principal reduction is clamped by the outstanding balance" do
    small = @user.money_sources.create!(name: "Casi pagado", kind: "loan")
    small.create_credit_account!(
      outstanding_balance: 100, interest_rate: 1.0, interest_rate_type: "monthly",
      installment_amount: 300, installment_count: 5, installments_paid: 0,
      start_date: Date.new(2026, 1, 5), payment_frequency: "monthly"
    )
    Credits::Projection::Builder.call(money_source: small)

    result = Credits::ExtraPayments::Create.call(
      money_source: small, funding_money_source: @account, date: Date.current,
      amount: "5000", application_type: "reduce_term"
    )

    assert result.success?
    assert_equal BigDecimal("100"), result.result.principal_reduction
    # Only 100 of the expense applied to capital; the loan is done.
    # Only 100 left the account (the expense matches what actually paid).
    assert_equal BigDecimal("0"), small.reload.credit_account.outstanding_balance.to_d
    assert_equal BigDecimal("500_000") - BigDecimal("100"), @account.reload.balance
  end

  test "rejects an unknown application type, bad source or missing projection" do
    bad = Credits::ExtraPayments::Create.call(money_source: @loan, funding_money_source: @account,
                                              date: Date.current, amount: "300", application_type: "whatever")
    assert bad.failure?

    foreign = User.create!(name: "Otro", email: "other-extra@example.com", password: "password123")
    foreign_account = foreign.money_sources.create!(name: "Ajena", kind: "account")
    other_user = Credits::ExtraPayments::Create.call(money_source: @loan, funding_money_source: foreign_account,
                                                     date: Date.current, amount: "300", application_type: "reduce_term")
    assert other_user.failure?

    no_projection = @user.money_sources.create!(name: "Sin proyección", kind: "loan")
    missing = Credits::ExtraPayments::Create.call(money_source: no_projection, funding_money_source: @account,
                                                  date: Date.current, amount: "300", application_type: "reduce_term")
    assert missing.failure?
  end
end

# Destroying a recorded extra payment destroys the real payment + expense;
# the standard callbacks revert the loan balance and the funding account.
class ExtraPaymentsReversalTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Reverse User", email: "reverse@example.com", password: "password123")
    @loan = @user.money_sources.create!(name: "Ref Loan", kind: "loan", sub_kind: "personal")
    @loan.create_credit_account!(
      outstanding_balance: 1_200, interest_rate: 1.0, interest_rate_type: "monthly",
      installment_amount: 300, installment_count: 5, installments_paid: 0,
      start_date: Date.new(2026, 1, 5), payment_frequency: "monthly"
    )
    @account = @user.money_sources.create!(name: "Ahorros", kind: "account", starting_balance: 500_000)
    Credits::Projection::Builder.call(money_source: @loan)
  end

  test "discarding restores balance, account and removes payment and expense" do
    payment = Credits::ExtraPayments::Create.call(
      money_source: @loan, funding_money_source: @account, date: Date.current,
      amount: "300", application_type: "reduce_term"
    ).result

    assert_equal BigDecimal("900"), @loan.credit_account.reload.outstanding_balance.to_d
    assert_equal BigDecimal("500_000") - BigDecimal("300"), @account.reload.balance

    payment.discard!

    assert_equal BigDecimal("1200"), @loan.credit_account.reload.outstanding_balance.to_d
    assert_equal BigDecimal("500_000"), @account.reload.balance
    assert Payment.find_by(id: payment.payment_id).nil?
    assert Transaction.find_by(id: payment.expense_id).nil?
    assert payment.frozen?
  end
end
