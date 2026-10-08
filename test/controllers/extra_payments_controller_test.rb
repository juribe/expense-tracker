# frozen_string_literal: true

require "test_helper"

# ExtraPaymentsController: REAL extraordinary payments for a user's loan,
# nested at /money_sources/:money_source_id/extra_payments. Creating applies
# a cash expense from a funding source + a principal-only payment to the
# debt; deleting reverts everything through the standard callbacks.
class ExtraPaymentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "Test User", email: "extras_ctrl@example.com", password: "password123")
    sign_in @user
    @loan = @user.money_sources.create!(name: "Hipotecario", kind: "loan", sub_kind: "mortgage")
    @loan.create_credit_account!(
      outstanding_balance: 1_200_000, interest_rate: 1.0, interest_rate_type: "monthly",
      installment_amount: 300_000, installment_count: 5, installments_paid: 0,
      start_date: Date.new(2026, 1, 5), payment_frequency: "monthly"
    )
    Credits::Projection::Builder.call(money_source: @loan).result
    @account = @user.money_sources.create!(name: "Ahorros", kind: "account", starting_balance: 500_000)
  end

  test "create records a real expense + payment and moves the balance" do
    balance_before = @loan.reload.credit_account.outstanding_balance.to_d

    post money_source_extra_payments_path(@loan), params: {
      date: Date.current, extra_amount: "300000", application_type: "reduce_term",
      funding_money_source_id: @account.id, note: "Aguinaldo"
    }

    assert_redirected_to money_source_path(@loan)
    extra = @loan.reload.credit_extra_payments.last
    assert_equal BigDecimal("300000"), extra.amount
    assert_equal BigDecimal("300000"), extra.principal_reduction

    # Real movements: the money left the funding account and the debt fell.
    assert_equal BigDecimal("200_000"), extra.funding_money_source.reload.balance
    assert_equal "expense", extra.expense.kind
    assert_equal balance_before - BigDecimal("300000"),
                 @loan.credit_account.reload.outstanding_balance.to_d
    # The payment joins the loan's own payment list.
    assert_includes @loan.reload.payments.map(&:id), extra.payment.id
  end

  test "create rejects a missing funding source" do
    post money_source_extra_payments_path(@loan), params: {
      date: Date.current, extra_amount: "300000", application_type: "reduce_term"
    }

    assert_redirected_to money_source_path(@loan)
    assert @loan.reload.credit_extra_payments.empty?
  end

  test "create rejects another user's funding source" do
    other = User.create!(name: "Otro", email: "other-extras@example.com", password: "password123")
    foreign = other.money_sources.create!(name: "Ajena", kind: "account")

    post money_source_extra_payments_path(@loan), params: {
      date: Date.current, extra_amount: "300000", application_type: "reduce_term",
      funding_money_source_id: foreign.id
    }

    assert_redirected_to money_source_path(@loan)
    assert @loan.reload.credit_extra_payments.empty?
  end

  test "another user's loan is not accessible" do
    other = User.create!(name: "Otro", email: "other2-extras@example.com", password: "password123")
    foreign = other.money_sources.create!(name: "Ajeno", kind: "loan")

    post money_source_extra_payments_path(foreign), params: {
      date: Date.current, extra_amount: "300000", application_type: "reduce_term"
    }

    assert_response :not_found
  end

  test "destroy reverses the payment, expense and balance" do
    extra = Credits::ExtraPayments::Create.call(
      money_source: @loan, funding_money_source: @account, date: Date.current,
      amount: "300000", application_type: "reduce_term"
    ).result

    assert_equal BigDecimal("900_000"), @loan.credit_account.reload.outstanding_balance.to_d

    delete money_source_extra_payment_path(@loan, extra)

    assert_redirected_to money_source_path(@loan)
    assert_equal BigDecimal("1_200_000"), @loan.credit_account.reload.outstanding_balance.to_d
    assert_equal BigDecimal("500_000"), @account.reload.balance
    assert Payment.find_by(id: extra.payment_id).nil?
    assert_equal 0, @loan.reload.credit_extra_payments.count
  end
end

# Revolving targets (credit cards / crédito rotativo) use the simplified
# abono: a transfer from the funding source lowers the balance directly.
class ExtraPaymentsRevolvingControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "Revolving Ctrl", email: "revolving-ctrl@example.com", password: "password123")
    sign_in @user
    @account = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 20_000_000)
  end

  test "create records a transfer-based abono on a credit card" do
    card = @user.money_sources.create!(name: "Tarjeta", kind: "credit_card", starting_balance: -8_000_000)
    card.create_credit_account!(credit_limit: 10_000_000)

    post money_source_extra_payments_path(card), params: {
      date: Date.current, extra_amount: "2000000", application_type: "reduce_balance",
      funding_money_source_id: @account.id
    }

    assert_redirected_to money_source_path(card)
    extra = card.reload.credit_extra_payments.last
    assert_equal "reduce_balance", extra.application_type
    assert_nil extra.expense_id
    assert_nil extra.payment_id
    assert extra.transfer_id.present?
    assert_equal BigDecimal("6_000_000"), card.used_credit
    assert_equal BigDecimal("4_000_000"), card.available_credit
    assert_equal BigDecimal("18_000_000"), @account.reload.balance
  end

  test "overpaying a credit card redirects with an alert and records nothing" do
    card = @user.money_sources.create!(name: "Tarjeta", kind: "credit_card", starting_balance: -500_000)
    card.create_credit_account!(credit_limit: 10_000_000)

    post money_source_extra_payments_path(card), params: {
      date: Date.current, extra_amount: "700000", application_type: "reduce_balance",
      funding_money_source_id: @account.id
    }

    assert_redirected_to money_source_path(card)
    assert_not flash[:alert].blank?
    assert_equal BigDecimal("500_000"), card.reload.used_credit
    assert_equal BigDecimal("20_000_000"), @account.reload.balance
    assert_equal 0, card.credit_extra_payments.count
  end
end

# The real abonos card lives on the credit's own page, never on the
# simulation page.
class ExtraPaymentsPlacementTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "Place User", email: "placement-extras@example.com", password: "password123")
    sign_in @user
  end

  test "the loan show page renders the real abonos card" do
    loan = @user.money_sources.create!(name: "Hipotecario", kind: "loan", sub_kind: "mortgage")
    loan.create_credit_account!(outstanding_balance: 1_000_000, payment_frequency: "monthly")

    get money_source_path(loan)

    assert_response :success
    assert_match "Abonos extraordinarios", @response.body
  end

  test "credit cards get the simplified abono extraordinario form" do
    card = @user.money_sources.create!(name: "Tarjeta", kind: "credit_card", starting_balance: -100_000)

    get money_source_path(card)

    assert_response :success
    assert_match "Abonos extraordinarios", @response.body
    assert_match "data-extra-preview", @response.body
    # The select (id extra_application_…) is amortizing-only; the simplified
    # form carries the application type as a hidden field instead.
    assert_no_match 'id="extra_application_', @response.body
  end

  test "revolving loans get the simplified abono extraordinario form too" do
    line = @user.money_sources.create!(name: "Rotativo", kind: "loan", sub_kind: "revolving")
    line.create_credit_account!(outstanding_balance: 4_000_000)

    get money_source_path(line)

    assert_response :success
    assert_match "Abonos extraordinarios", @response.body
    assert_match "data-extra-preview", @response.body
  end

  test "the credits simulation page never renders the abonos card" do
    loan = @user.money_sources.create!(name: "Hipotecario", kind: "loan", sub_kind: "mortgage")
    loan.create_credit_account!(
      outstanding_balance: 1_200_000, interest_rate: 1.0, interest_rate_type: "monthly",
      installment_amount: 300_000, installment_count: 5, installments_paid: 0,
      start_date: Date.new(2026, 1, 5), payment_frequency: "monthly"
    )
    Credits::Projection::Builder.call(money_source: loan).result

    get money_source_credits_path(loan)

    assert_response :success
    # The simulation page carries no abono form (only the deferred copy).
    assert_no_match "extra_payments/create", @response.body
    assert_no_match "/extra_payments\">", @response.body
  end
end
