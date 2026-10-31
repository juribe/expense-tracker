# frozen_string_literal: true

require "test_helper"
require_relative "../../support/mcp_tool_helper"

class BudgetToolsTest < ActiveSupport::TestCase
  include McpToolHelper

  setup do
    @user = User.create!(name: "MCP Budgets", email: "mcp_budgets@example.com", password: "password123")
    @other_user = User.create!(name: "Other", email: "mcp_budgets_other@example.com", password: "password123")
    @category = Category.create!(name: "Transporte Presupuesto", is_default: true, category_type: "expense")
    @account = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 5_000_000)
    @budget = Budget.create!(user: @user, category: @category, monthly_amount: 800_000)

    Expense.create!(user: @user, category: @category, money_source: @account, amount: 620_000,
                    date: Date.current, description: "Bus")
    @foreign_budget = Budget.create!(user: @other_user, category: @category, monthly_amount: 100_000)
  end

  test "lists budgets with spent, remaining and percentage" do
    payload = invoke_tool(Mcp::Tools::Budgets::GetBudgetsTool, user: @user)
    budget = payload.dig("data", "budgets").find { |row| row["id"] == @budget.id }

    assert_equal "800000.0", budget["amount"]
    assert_equal "620000.0", budget["spent"]
    assert_equal "180000.0", budget["remaining"]
    assert_equal 77.5, budget["percentage"]
    assert_equal "on_track", budget["status"]
  end

  test "returns one budget for an explicit month" do
    previous_month = (Date.current - 1.month)
    Expense.create!(user: @user, category: @category, money_source: @account, amount: 100_000,
                    date: previous_month.beginning_of_month + 2.days, description: "Mes anterior")

    payload = invoke_tool(Mcp::Tools::Budgets::GetBudgetDetailsTool, user: @user,
                          budget_id: @budget.id, month: previous_month.strftime("%Y-%m"))

    assert_equal "100000.0", payload.dig("data", "spent")
  end

  test "returns progress for every active budget" do
    payload = invoke_tool(Mcp::Tools::Budgets::GetBudgetProgressTool, user: @user)

    assert_equal [ @budget.id ], payload.dig("data", "budgets").map { |row| row["id"] }
  end

  test "does not find another user's budget" do
    payload = invoke_tool(Mcp::Tools::Budgets::GetBudgetDetailsTool, user: @user, budget_id: @foreign_budget.id)

    assert_equal false, payload["success"]
    assert_equal "NOT_FOUND", payload.dig("error", "code")
  end

  test "rejects an invalid month" do
    payload = invoke_tool(Mcp::Tools::Budgets::GetBudgetProgressTool, user: @user, month: "2026-13")

    assert_equal false, payload["success"]
    assert_equal "INVALID_DATE_RANGE", payload.dig("error", "code")
  end
end
