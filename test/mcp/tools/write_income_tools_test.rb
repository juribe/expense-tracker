# frozen_string_literal: true

require "test_helper"
require_relative "../../support/mcp_tool_helper"

class WriteIncomeToolsTest < ActiveSupport::TestCase
  include McpToolHelper

  setup do
    @user = User.create!(name: "MCP Write Incomes", email: "mcp_write_incomes@example.com", password: "password123")
    @other_user = User.create!(name: "Other", email: "mcp_write_incomes_other@example.com", password: "password123")
    @income_category = Category.create!(name: "Salario Escritura", is_default: true, category_type: "income")
    @expense_category = Category.create!(name: "Gasto Escritura", is_default: true, category_type: "expense")
    @account = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 0)
    @foreign_income = Income.create!(
      user: @other_user, category: @income_category,
      money_source: @other_user.money_sources.create!(name: "Ajena", kind: "account", starting_balance: 0),
      amount: 1000, date: Date.current, description: "Ajena"
    )
  end

  test "creates an income and increases the balance" do
    payload = invoke_tool(Mcp::Tools::Incomes::CreateIncomeTool, user: @user,
                          amount: "3000000", date: Date.current.iso8601,
                          category_id: @income_category.id, money_source_id: @account.id,
                          description: "Salario")

    assert_equal true, payload["success"]
    income = Income.find(payload.dig("data", "id"))
    assert_equal BigDecimal("3000000"), income.amount
    assert_equal BigDecimal("3000000"), @account.reload.balance
  end

  test "rejects an expense category for an income" do
    assert_no_difference "Income.count" do
      payload = invoke_tool(Mcp::Tools::Incomes::CreateIncomeTool, user: @user,
                            amount: "1000", date: Date.current.iso8601,
                            category_id: @expense_category.id, money_source_id: @account.id,
                            description: "X")

      assert_equal false, payload["success"]
      assert_equal "INVALID_CATEGORY", payload.dig("error", "code")
    end
  end

  test "updates the amount and resyncs the balance" do
    income = Income.create!(user: @user, category: @income_category, money_source: @account,
                            amount: 1_000_000, date: Date.current, description: "Salario")

    payload = invoke_tool(Mcp::Tools::Incomes::UpdateIncomeTool, user: @user,
                          income_id: income.id, amount: "1500000")

    assert_equal true, payload["success"]
    assert_equal BigDecimal("1500000"), income.reload.amount
    assert_equal BigDecimal("1500000"), @account.reload.balance
  end

  test "does not update another user's income" do
    payload = invoke_tool(Mcp::Tools::Incomes::UpdateIncomeTool, user: @user,
                          income_id: @foreign_income.id, amount: "1")

    assert_equal false, payload["success"]
    assert_equal "NOT_FOUND", payload.dig("error", "code")
  end
end
