# frozen_string_literal: true

require "test_helper"
require_relative "../../support/mcp_tool_helper"

class IncomeToolsTest < ActiveSupport::TestCase
  include McpToolHelper

  setup do
    @user = User.create!(name: "MCP Incomes", email: "mcp_incomes@example.com", password: "password123")
    @other_user = User.create!(name: "Other", email: "mcp_incomes_other@example.com", password: "password123")
    @income_category = Category.create!(name: "Salario MCP", is_default: true, category_type: "income")
    @expense_category = Category.create!(name: "Gasto MCP", is_default: true, category_type: "expense")
    @account = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 0)
    @other_account = @other_user.money_sources.create!(name: "Cuenta Ajena", kind: "account", starting_balance: 0)

    @salary = Income.create!(user: @user, category: @income_category, money_source: @account,
                             amount: 3_000_000, date: Date.current, description: "Salario")
    @foreign_income = Income.create!(user: @other_user, category: @income_category, money_source: @other_account,
                                     amount: 9_000_000, date: Date.current, description: "Ajena")
  end

  test "lists incomes for the current period" do
    payload = invoke_tool(Mcp::Tools::Incomes::GetIncomesTool, user: @user)

    ids = payload.dig("data", "incomes").map { |income| income["id"] }
    assert_equal [ @salary.id ], ids
    assert_not_includes ids, @foreign_income.id
  end

  test "returns positive amounts and the income category" do
    payload = invoke_tool(Mcp::Tools::Incomes::GetIncomeTool, user: @user, income_id: @salary.id)
    income = payload["data"]

    assert_equal "3000000.0", income["amount"]
    assert_equal "income", income["kind"]
    assert_equal @income_category.id, income.dig("category", "id")
  end

  test "does not find another user's income" do
    payload = invoke_tool(Mcp::Tools::Incomes::GetIncomeTool, user: @user, income_id: @foreign_income.id)

    assert_equal false, payload["success"]
    assert_equal "NOT_FOUND", payload.dig("error", "code")
  end

  test "rejects an expense category when filtering incomes" do
    payload = invoke_tool(Mcp::Tools::Incomes::GetIncomesTool, user: @user, category_id: @expense_category.id)

    assert_equal false, payload["success"]
    assert_equal "INVALID_CATEGORY", payload.dig("error", "code")
  end
end
