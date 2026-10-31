# frozen_string_literal: true

require "test_helper"
require_relative "../../support/mcp_tool_helper"

class WritePaymentToolsTest < ActiveSupport::TestCase
  include McpToolHelper

  setup do
    @user = User.create!(name: "MCP Payments", email: "mcp_payments@example.com", password: "password123")
    @other_user = User.create!(name: "Other", email: "mcp_payments_other@example.com", password: "password123")
    @category = Category.create!(name: "Compras Pago", is_default: true, category_type: "expense")
    @account = @user.money_sources.create!(name: "Ahorros", kind: "account", starting_balance: 5_000_000)
    @card = @user.money_sources.create!(name: "Visa", kind: "credit_card", starting_balance: 0)
    CreditAccount.create!(money_source: @card, credit_limit: 2_000_000, payment_due_day: 15)
    @loan = @user.money_sources.create!(name: "Hipoteca", kind: "loan", starting_balance: 0)
    CreditAccount.create!(money_source: @loan, principal_amount: 10_000_000, outstanding_balance: 6_000_000,
                          installment_amount: 500_000, installment_count: 20, interest_rate: 1.5,
                          interest_rate_type: "monthly", payment_due_day: 15)

    Expense.create!(user: @user, category: @category, money_source: @card, amount: 300_000,
                    date: Date.current, description: "Compra")

    @foreign_card = @other_user.money_sources.create!(name: "Ajena", kind: "credit_card", starting_balance: 0)
    CreditAccount.create!(money_source: @foreign_card, credit_limit: 500_000)
  end

  test "pays a credit card through the existing payment mechanism" do
    payload = invoke_tool(Mcp::Tools::CreditCards::CreateCreditCardPaymentTool, user: @user,
                          amount: "300000", date: Date.current.iso8601,
                          account_id: @account.id, credit_card_id: @card.id,
                          description: "Abono tarjeta")

    assert_equal true, payload["success"]
    assert_equal "300000.0", payload.dig("data", "amount")
    assert_equal "300000.0", payload.dig("data", "principal_amount")
    assert_equal BigDecimal("4700000"), @account.reload.balance
    assert_equal 0.to_d, @card.reload.used_credit

    payment = Payment.find(payload.dig("data", "id"))
    assert_equal @card.id, payment.money_source_id
    assert_equal I18n.t("categories.debt_payments"), payment.expense.category.name
  end

  test "creates exactly one expense and one payment" do
    assert_difference [ "Expense.count", "Payment.count" ], 1 do
      invoke_tool(Mcp::Tools::CreditCards::CreateCreditCardPaymentTool, user: @user,
                  amount: "300000", date: Date.current.iso8601,
                  account_id: @account.id, credit_card_id: @card.id, description: "Abono")
    end
  end

  test "pays a loan and lowers its outstanding balance" do
    payload = invoke_tool(Mcp::Tools::Debts::CreateDebtPaymentTool, user: @user,
                          amount: "500000", date: Date.current.iso8601,
                          debt_id: @loan.id, source_id: @account.id,
                          description: "Cuota")

    assert_equal true, payload["success"]
    assert_equal BigDecimal("5500000"), @loan.credit_account.reload.outstanding_balance
    assert_equal BigDecimal("4500000"), @account.reload.balance
  end

  test "accepts an explicit distribution that sums to the amount" do
    payload = invoke_tool(Mcp::Tools::CreditCards::CreateCreditCardPaymentTool, user: @user,
                          amount: "300000", date: Date.current.iso8601,
                          account_id: @account.id, credit_card_id: @card.id,
                          principal_amount: "200000", interest_amount: "100000",
                          description: "Abono con intereses")

    assert_equal true, payload["success"]
    assert_equal "200000.0", payload.dig("data", "principal_amount")
    assert_equal "100000.0", payload.dig("data", "interest_amount")
  end

  test "rejects a distribution that does not sum to the amount" do
    assert_no_difference [ "Expense.count", "Payment.count" ] do
      payload = invoke_tool(Mcp::Tools::CreditCards::CreateCreditCardPaymentTool, user: @user,
                            amount: "300000", date: Date.current.iso8601,
                            account_id: @account.id, credit_card_id: @card.id,
                            principal_amount: "100000", description: "Mala")

      assert_equal false, payload["success"]
      assert_equal "INVALID_ARGUMENT", payload.dig("error", "code")
    end
  end

  test "rejects a pocket as the funding source" do
    pocket = @user.money_sources.create!(name: "Bolsa", kind: "pocket", starting_balance: 1_000_000)

    payload = invoke_tool(Mcp::Tools::CreditCards::CreateCreditCardPaymentTool, user: @user,
                          amount: "100000", date: Date.current.iso8601,
                          account_id: pocket.id, credit_card_id: @card.id, description: "X")

    assert_equal false, payload["success"]
    assert_equal "INVALID_MONEY_SOURCE", payload.dig("error", "code")
  end

  test "does not pay another user's card" do
    payload = invoke_tool(Mcp::Tools::CreditCards::CreateCreditCardPaymentTool, user: @user,
                          amount: "100000", date: Date.current.iso8601,
                          account_id: @account.id, credit_card_id: @foreign_card.id, description: "X")

    assert_equal false, payload["success"]
    assert_equal "NOT_FOUND", payload.dig("error", "code")
  end

  test "is idempotent for the same payment key" do
    key = SecureRandom.uuid
    arguments = { amount: "300000", date: Date.current.iso8601, account_id: @account.id,
                  credit_card_id: @card.id, description: "Abono", idempotency_key: key }

    first = invoke_tool(Mcp::Tools::CreditCards::CreateCreditCardPaymentTool, user: @user, **arguments)
    assert_equal true, first["success"]

    assert_no_difference [ "Expense.count", "Payment.count" ] do
      second = invoke_tool(Mcp::Tools::CreditCards::CreateCreditCardPaymentTool, user: @user, **arguments)
      assert_equal first.dig("data", "id"), second.dig("data", "id")
    end
  end
end
