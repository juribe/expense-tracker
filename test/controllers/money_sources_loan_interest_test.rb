# frozen_string_literal: true

require "test_helper"

class MoneySourcesLoanInterestTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "Loan Interest Controller", email: "loan_interest_ctrl@example.com",
                         password: "password123")
    sign_in @user
    @loan = create_loan
  end

  def create_loan(active: true, enabled: true, day: 11)
    loan = @user.money_sources.create!(name: "Hipotecario", kind: "loan", sub_kind: "mortgage", active: active)
    loan.create_credit_account!(
      principal_amount: 170_900_000,
      outstanding_balance: 67_166_819.12,
      interest_rate: 18.05,
      interest_rate_type: "effective_annual",
      interest_calculation_enabled: enabled,
      interest_calculation_day: day,
      start_date: Date.new(2025, 1, 11),
      installment_amount: 1_130_575,
      installment_count: 192,
      installments_paid: 117,
      payment_frequency: "monthly"
    )
    loan
  end

  def create_payment(loan, date:, principal: 400_000, interest: 100_000)
    account = @user.money_sources.create!(name: "Ahorros pago", kind: "account", starting_balance: 5_000_000)
    category = Category.create!(user: @user, name: "Pagos#{SecureRandom.hex(2)}")
    expense = @user.expenses.create!(
      category: category, description: "Cuota", amount: principal + interest,
      kind: "expense", source: "manual", date: date, money_source: account
    )
    Payment.create!(
      user: @user, expense: expense, money_source: loan, amount: principal + interest,
      principal_amount: principal, interest_amount: interest
    )
    loan.credit_account.reload
  end

  test "loan summary labels the principal and shows the estimated interest section" do
    get money_source_path(@loan)

    assert_response :success
    assert_select "[data-testid=loan-principal-balance].debt-panel-balance-value"
    assert_select "[data-testid=loan-principal-label].debt-panel-balance-label", text: I18n.t("money_sources.show.loan_principal")
    assert_select ".debt-panel-badges .badge", minimum: 1
    assert_select ".debt-panel-metrics .debt-panel-metric-value", count: 2
    assert_select ".debt-panel-caption"
    assert_select "[data-testid=loan-accrued-interest]" do
      assert_select "*", text: /#{I18n.t("money_sources.show.accrued_interest")}/
      assert_select "[data-testid=loan-estimated-total]"
      assert_select ".loan-interest-summary-badge", text: I18n.t("money_sources.show.estimated_badge")
      assert_select ".loan-interest-summary-metric", count: 2
      assert_select ".loan-interest-summary-metric dt", text: I18n.t("money_sources.show.applied_rate")
      assert_select ".loan-interest-summary-metric dt", text: I18n.t("money_sources.show.daily_interest")
      assert_select ".loan-interest-summary-disclaimer"
    end
  end

  test "disabled loans keep the principal label and hide the estimated interest section" do
    loan = create_loan(enabled: false)

    get money_source_path(loan)

    assert_response :success
    assert_select "[data-testid=loan-principal-balance]"
    assert_select "[data-testid=loan-accrued-interest]", count: 0
  end

  test "inactive loans do not show estimated interest" do
    loan = create_loan(active: false)

    get money_source_path(loan)

    assert_response :success
    assert_select "[data-testid=loan-accrued-interest]", count: 0
  end

  test "enabled loans without a reference day show an explanatory message" do
    loan = create_loan(day: nil)
    loan.credit_account.update_column(:interest_calculation_day, nil)
    loan.credit_account.update_column(:start_date, nil)

    get money_source_path(loan)

    assert_response :success
    assert_select "[data-testid=loan-accrued-interest]", count: 0
    assert_select "[data-testid=loan-interest-unavailable]"
  end

  test "principal balance is still the reconciled outstanding balance, not the estimate" do
    get money_source_path(@loan)

    assert_select "[data-testid=loan-principal-balance]", text: /67\.166\.819/
    assert_no_match(/67\.446\.380/, response.body)
  end

  test "a payment with interest shows zero and the next cycle date" do
    travel_to(Date.new(2026, 11, 20)) do
      create_payment(@loan, date: Date.new(2026, 11, 15))

      get money_source_path(@loan)

      assert_response :success
      assert_select "[data-testid=loan-accrued-interest]"
      assert_select "[data-testid=loan-accrued-interest-amount]", text: /\$0/
      assert_select "[data-testid=loan-interest-resumes]", text: /11 de Diciembre de 2026/
    end
  end

  test "bank comparison calculates the difference without changing financial records" do
    assert_no_difference -> { Payment.count } do
      assert_no_difference -> { Expense.count } do
        assert_no_difference -> { @loan.credit_account.reload.outstanding_balance } do
          get money_source_path(@loan, bank_balance: "67.000.000")
        end
      end
    end

    assert_response :success
    assert_select "[data-testid=loan-bank-comparison]"
    assert_select "[data-testid=bank-reported-balance]", text: /67\.000\.000/
    assert_select "[data-testid=bank-comparison-difference]"
  end

  test "an invalid bank balance does not persist anything" do
    assert_no_difference -> { Payment.count } do
      get money_source_path(@loan, bank_balance: "no-es-un-numero")
    end

    assert_response :success
    assert_select "[data-testid=bank-comparison-error]"
  end

  test "loan form exposes the monthly interest settings" do
    get edit_money_source_path(@loan)

    assert_response :success
    assert_select "input#money_source_credit_account_attributes_interest_calculation_enabled"
    assert_select "input#money_source_credit_account_attributes_interest_calculation_day"
    assert_select "input#loan_interest_calculation_frequency[readonly]"
    assert_select "input#loan_outstanding_balance_display[readonly]"
    assert_select "#loan-interest-calculation"
    assert_select ".loan-interest-section"
    assert_select ".loan-interest-panel"
    assert_select ".loan-interest-note"
    assert_select ".loan-interest-state-on", text: I18n.t("money_sources.form.interest_calculation_state_on")
    assert_select "input#loan_outstanding_balance_display.loan-readonly-field[readonly]"
  end

  test "loan form no longer exposes payment frequency or the last payment date" do
    get edit_money_source_path(@loan)

    assert_select "select#money_source_credit_account_attributes_payment_frequency", count: 0
    assert_select "input#money_source_credit_account_attributes_end_date", count: 0
    assert_select "input#money_source_credit_account_attributes_start_date"
  end

  test "interest calculation settings persist through the loan form" do
    patch money_source_path(@loan), params: {
      money_source: {
        credit_account_attributes: {
          id: @loan.credit_account.id,
          interest_calculation_enabled: "1",
          interest_calculation_day: "10"
        }
      }
    }

    assert_redirected_to money_sources_loans_path
    account = @loan.reload.credit_account
    assert account.interest_calculation_enabled?
    assert_equal 10, account.interest_calculation_day
  end

  test "creating a loan persists the interest settings" do
    assert_difference -> { MoneySource.count }, 1 do
      post money_sources_path, params: {
        money_source: {
          name: "Nuevo Hipotecario",
          kind: "loan",
          sub_kind: "mortgage",
          active: "1",
          credit_account_attributes: {
            principal_amount: "170900000",
            outstanding_balance: "67166819.12",
            interest_rate: "18.05",
            interest_rate_type: "effective_annual",
            interest_calculation_enabled: "1",
            interest_calculation_day: "11",
            start_date: "2023-06-13"
          }
        }
      }
    end

    assert_redirected_to money_sources_loans_path
    account = MoneySource.find_by(name: "Nuevo Hipotecario").credit_account
    assert account.interest_calculation_enabled?
    assert_equal 11, account.interest_calculation_day
  end

  test "a legacy loan without credit account persists the interest settings" do
    loan = @user.money_sources.create!(name: "Legacy Loan", kind: "loan", active: true)
    assert_nil loan.credit_account

    patch money_source_path(loan), params: {
      money_source: {
        name: "Legacy Loan",
        kind: "loan",
        active: "1",
        credit_account_attributes: {
          interest_calculation_enabled: "1",
          interest_calculation_day: "11"
        }
      }
    }

    assert_redirected_to money_sources_loans_path
    account = loan.reload.credit_account
    assert account.present?
    assert account.interest_calculation_enabled?
    assert_equal 11, account.interest_calculation_day
  end

  test "a blank day is filled from the first payment date on save" do
    loan = @user.money_sources.create!(name: "Auto day", kind: "loan", active: true)
    loan.create_credit_account!(outstanding_balance: 10_000_000, interest_rate: 18.05,
                                interest_rate_type: "effective_annual", start_date: Date.new(2026, 1, 15))

    patch money_source_path(loan), params: {
      money_source: {
        credit_account_attributes: { id: loan.credit_account.id, interest_calculation_enabled: "1" }
      }
    }

    assert_equal 15, loan.reload.credit_account.interest_calculation_day
  end
end
