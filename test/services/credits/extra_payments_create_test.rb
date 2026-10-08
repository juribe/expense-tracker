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
    # The expense is a debt payment, not uncategorized spending.
    assert_equal I18n.t("categories.debt_payments"), payment.expense.category.name
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

# Revolving products (credit cards and crédito rotativo) take a deliberately
# simpler extraordinary payment: a Transfer from the funding source lowers
# the outstanding balance. No Expense (§ accounting: the payment is a debt
# movement, not new spending), no Payment distribution, no schedule,
# no installments — the same balance the rest of the app uses.
class ExtraPaymentsRevolvingCardTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Revolving User", email: "revolving_card@example.com", password: "password123")
    @account = @user.money_sources.create!(name: "Cuenta Davibank", kind: "account", starting_balance: 20_000_000)
  end

  def create_card(used: 8_000_000, credit_limit: nil)
    @user.money_sources.create!(name: "Tarjeta", kind: "credit_card", starting_balance: -used).tap do |card|
      card.create_credit_account!(credit_limit: credit_limit)
    end
  end

  def record(card, amount, date: Date.new(2026, 10, 8))
    Credits::ExtraPayments::Create.call(money_source: card, funding_money_source: @account,
                                        date: date, amount: amount, application_type: "reduce_balance")
  end

  test "an extraordinary payment lowers the balance and raises the available credit" do
    card = create_card(credit_limit: 10_000_000)
    extra = nil

    assert_no_difference [ "Expense.count", "Payment.count", "Transaction.count" ] do
      result = record(card, 2_000_000)
      assert result.success?
      extra = result.result
    end

    assert_equal "reduce_balance", extra.application_type
    transfer = extra.transfer
    assert transfer.present?
    assert_equal @account.id, transfer.from_source_id
    assert_equal card.id, transfer.to_source_id
    assert_equal BigDecimal("2_000_000"), transfer.amount

    assert_equal BigDecimal("6_000_000"), card.reload.used_credit
    assert_equal BigDecimal("4_000_000"), card.available_credit
    assert_equal 60.0, card.credit_utilization
    assert_equal BigDecimal("18_000_000"), @account.reload.balance
    assert_equal BigDecimal("8_000_000"), extra.effect["balance_before"].to_d
    assert_equal BigDecimal("6_000_000"), extra.effect["balance_after"].to_d
  end

  test "without a credit limit only the balance changes" do
    card = create_card(used: 8_000_000)

    result = record(card, 3_000_000)

    assert result.success?
    assert_equal BigDecimal("5_000_000"), card.reload.used_credit
    assert_nil card.available_credit
  end

  test "a payment equal to the balance zeroes the debt" do
    card = create_card(used: 500_000)

    result = record(card, 500_000)

    assert result.success?
    assert_equal BigDecimal("0"), card.reload.used_credit
  end

  test "a payment greater than the balance is rejected and nothing is recorded" do
    card = create_card(used: 500_000, credit_limit: 10_000_000)

    assert_no_difference [ "Transfer.count", "CreditExtraPayment.count" ] do
      result = record(card, 700_000)
      assert result.failure?
      assert result.errors.any?
    end

    assert_equal BigDecimal("500_000"), card.reload.used_credit
    assert_equal BigDecimal("20_000_000"), @account.reload.balance
  end

  test "multiple extraordinary payments accumulate on the reduced balance" do
    card = create_card(credit_limit: 10_000_000)

    assert record(card, 2_000_000).success?
    assert record(card, 1_500_000, date: Date.new(2026, 10, 9)).success?

    assert_equal BigDecimal("4_500_000"), card.reload.used_credit
    assert_equal 2, card.credit_extra_payments.count
  end

  test "a purchase after the payment raises the balance from the reduced base" do
    card = create_card(credit_limit: 10_000_000)
    record(card, 2_000_000)

    Expense.create!(user: @user, amount: 350_000, description: "Compra",
                    date: Date.new(2026, 10, 9), kind: "expense", source: "manual", money_source: card)

    assert_equal BigDecimal("6_350_000"), card.reload.used_credit
  end

  test "regular statement payment and extraordinary payment work independently" do
    card = create_card(credit_limit: 10_000_000)
    category = Category.create!(name: "Pago de deuda", user: @user, category_type: "expense")
    expense = Expenses::Create.call(user: @user, amount: 1_500_000, description: "Pago tarjeta",
                                    category: category, occurred_at: Date.new(2026, 10, 5),
                                    source: "manual", money_source: @account)
    result = Payments::Apply.call(user: @user, money_source: card, expense: expense,
                                  distribution: { principal_amount: "1500000" })
    assert result.success?

    assert record(card, 2_000_000).success?

    assert_equal BigDecimal("4_500_000"), card.reload.used_credit
    assert_equal 1, card.payments.count
    assert_equal 1, card.credit_extra_payments.where(application_type: "reduce_balance").count
  end

  test "reduce_balance is not accepted on a non-revolving product" do
    mortgage = @user.money_sources.create!(name: "Hipotecario", kind: "loan", sub_kind: "mortgage")
    mortgage.create_credit_account!(outstanding_balance: 8_000_000)

    result = record(mortgage, 2_000_000)

    assert result.failure?
    assert_equal BigDecimal("8_000_000"), mortgage.reload.credit_account.outstanding_balance.to_d
  end
end

class ExtraPaymentsRevolvingLoanTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Revolving Loan User", email: "revolving_loan@example.com", password: "password123")
    @account = @user.money_sources.create!(name: "Cuenta Davibank", kind: "account", starting_balance: 20_000_000)
    @line = @user.money_sources.create!(name: "Crédito Rotativo", kind: "loan", sub_kind: "revolving",
                                        starting_balance: 0)
    @line.create_credit_account!(outstanding_balance: 8_000_000, credit_limit: 10_000_000)
    @line.reload
  end

  def record(amount, **overrides)
    Credits::ExtraPayments::Create.call(
      **{ money_source: @line, funding_money_source: @account, date: Date.new(2026, 10, 8),
          amount: amount, application_type: "reduce_balance" }.merge(overrides)
    )
  end

  test "the payment lowers the outstanding balance and frees the credit limit" do
    assert_no_difference [ "Expense.count", "Payment.count" ] do
      assert record(2_000_000).success?
    end

    assert_equal BigDecimal("6_000_000"), @line.reload.credit_account.outstanding_balance.to_d
    assert_equal BigDecimal("4_000_000"), @line.available_credit
    assert_equal BigDecimal("18_000_000"), @account.reload.balance
  end

  test "a new usage (disbursement/purchase) after the payment raises the balance from the reduced base" do
    record(2_000_000)

    Expense.create!(user: @user, amount: 1_000_000, description: "Giro",
                    date: Date.new(2026, 10, 9), kind: "expense", source: "manual", money_source: @line)

    assert_equal BigDecimal("7_000_000"), @line.reload.credit_account.outstanding_balance.to_d
  end

  test "overpaying the line is rejected" do
    assert_no_difference [ "Transfer.count", "CreditExtraPayment.count" ] do
      result = record(9_000_000)
      assert result.failure?
    end

    assert_equal BigDecimal("8_000_000"), @line.reload.credit_account.outstanding_balance.to_d
  end
end

class ExtraPaymentsRevolvingReversalTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Revolving Reverse", email: "revolving_reverse@example.com", password: "password123")
    @account = @user.money_sources.create!(name: "Cuenta Davibank", kind: "account", starting_balance: 20_000_000)
    @card = @user.money_sources.create!(name: "Tarjeta", kind: "credit_card", starting_balance: -8_000_000)
    @card.create_credit_account!(credit_limit: 10_000_000)
  end

  test "discarding an extraordinary payment destroys the transfer and restores both balances" do
    result = Credits::ExtraPayments::Create.call(money_source: @card, funding_money_source: @account,
                                                 date: Date.current, amount: "2000000",
                                                 application_type: "reduce_balance")
    extra = result.result
    transfer_id = extra.transfer_id

    assert_equal BigDecimal("18_000_000"), @account.reload.balance
    assert_equal BigDecimal("6_000_000"), @card.reload.used_credit

    extra.discard!

    assert_equal BigDecimal("8_000_000"), @card.reload.used_credit
    assert_equal BigDecimal("20_000_000"), @account.reload.balance
    assert Transfer.find_by(id: transfer_id).nil?
    assert extra.frozen?
  end
end
