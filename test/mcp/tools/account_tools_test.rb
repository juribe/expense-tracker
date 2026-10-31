# frozen_string_literal: true

require "test_helper"
require_relative "../../support/mcp_tool_helper"

class AccountToolsTest < ActiveSupport::TestCase
  include McpToolHelper

  setup do
    @user = User.create!(name: "MCP Accounts", email: "mcp_accounts@example.com", password: "password123")
    @other_user = User.create!(name: "Other", email: "mcp_accounts_other@example.com", password: "password123")
    @category = Category.create!(name: "Compras MCP", is_default: true, category_type: "expense")

    @account = @user.money_sources.create!(name: "Ahorros", kind: "account", starting_balance: 2_000_000)
    @cash = @user.money_sources.create!(name: "Efectivo", kind: "cash", starting_balance: 100_000)
    @debit = @user.money_sources.create!(name: "Débito", kind: "debit_card", parent: @account, starting_balance: 0)
    @card = @user.money_sources.create!(name: "Visa", kind: "credit_card", starting_balance: 0)
    CreditAccount.create!(money_source: @card, credit_limit: 1_000_000, statement_day: 5,
                          payment_due_day: 15, card_last_four: "1234")
    @loan = @user.money_sources.create!(name: "Hipoteca", kind: "loan", starting_balance: 0)
    CreditAccount.create!(money_source: @loan, principal_amount: 10_000_000, outstanding_balance: 6_000_000,
                          installment_amount: 500_000, installment_count: 20, interest_rate: 1.5,
                          interest_rate_type: "monthly", payment_due_day: 15)

    Expense.create!(user: @user, category: @category, money_source: @card, amount: 300_000,
                    date: Date.current, description: "Compra tarjeta")

    @foreign_card = @other_user.money_sources.create!(name: "Ajena", kind: "credit_card", starting_balance: 0)
    CreditAccount.create!(money_source: @foreign_card, credit_limit: 500_000)
  end

  test "lists accounts, cash and debit cards but not debts or pockets" do
    payload = invoke_tool(Mcp::Tools::Accounts::GetAccountsTool, user: @user)
    ids = payload.dig("data", "accounts").map { |account| account["id"] }

    assert_equal [ @account.id, @debit.id, @cash.id ].sort, ids.sort
    debit = payload.dig("data", "accounts").find { |account| account["id"] == @debit.id }
    assert_equal @account.id, debit["parent_id"]
  end

  test "returns balances and the liquid total" do
    payload = invoke_tool(Mcp::Tools::Accounts::GetAccountBalancesTool, user: @user)

    assert_equal "2100000.0", payload.dig("data", "total_liquid")
    balances = payload.dig("data", "accounts").index_by { |account| account["id"] }
    assert_equal "2000000.0", balances.dig(@account.id, "balance")
  end

  test "does not issue one query per account when listing balances" do
    4.times do |index|
      @user.money_sources.create!(name: "Cuenta #{index}", kind: "account", starting_balance: 1_000)
    end

    queries = count_queries { invoke_tool(Mcp::Tools::Accounts::GetAccountBalancesTool, user: @user) }

    assert_equal 1, queries
  end

  test "does not issue one query per account when listing accounts" do
    4.times do |index|
      @user.money_sources.create!(name: "Cuenta #{index}", kind: "account", starting_balance: 1_000)
    end

    queries = count_queries { invoke_tool(Mcp::Tools::Accounts::GetAccountsTool, user: @user) }

    assert_equal 1, queries
  end

  test "lists credit cards with limit, usage and dates" do
    payload = invoke_tool(Mcp::Tools::CreditCards::GetCreditCardsTool, user: @user)
    cards = payload.dig("data", "credit_cards")

    assert_equal [ @card.id ], cards.map { |card| card["id"] }
    card = cards.first
    assert_equal "1000000.0", card["credit_limit"]
    assert_equal "300000.0", card["used_credit"]
    assert_equal "700000.0", card["available_credit"]
    assert_equal 30.0, card["utilization_pct"]
    assert_equal "2026-11-15", card["next_payment_date"]
  end

  test "returns one credit card and rejects a loan id" do
    payload = invoke_tool(Mcp::Tools::CreditCards::GetCreditCardDetailsTool, user: @user, credit_card_id: @card.id)
    assert_equal @card.id, payload.dig("data", "id")

    payload = invoke_tool(Mcp::Tools::CreditCards::GetCreditCardDetailsTool, user: @user, credit_card_id: @loan.id)
    assert_equal false, payload["success"]
    assert_equal "INVALID_CREDIT_CARD", payload.dig("error", "code")
  end

  test "lists every debt with its outstanding balance" do
    payload = invoke_tool(Mcp::Tools::Debts::GetDebtsTool, user: @user)
    debts = payload.dig("data", "debts").index_by { |debt| debt["id"] }

    assert_equal [ @card.id, @loan.id ].sort, debts.keys.sort
    assert_equal "300000.0", debts.dig(@card.id, "outstanding_balance")
    assert_equal "6000000.0", debts.dig(@loan.id, "outstanding_balance")
  end

  test "returns loan details with installment, rate and next payment" do
    payload = invoke_tool(Mcp::Tools::Debts::GetDebtDetailsTool, user: @user, debt_id: @loan.id)
    debt = payload["data"]

    assert_equal "loan", debt["kind"]
    assert_equal "500000.0", debt["installment_amount"]
    assert_equal "1.5", debt["interest_rate"]
    assert_equal "2026-11-15", debt["next_payment_date"]
    assert_equal 12, debt["remaining_installments"]
    assert_equal 60.0, debt["progress_pct"]
  end

  test "does not find another user's credit card" do
    payload = invoke_tool(Mcp::Tools::CreditCards::GetCreditCardDetailsTool, user: @user,
                          credit_card_id: @foreign_card.id)

    assert_equal false, payload["success"]
    assert_equal "NOT_FOUND", payload.dig("error", "code")
  end
end
