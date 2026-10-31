# frozen_string_literal: true

require "test_helper"
require_relative "../../support/mcp_tool_helper"

class ReportToolsTest < ActiveSupport::TestCase
  include McpToolHelper

  setup do
    @user = User.create!(name: "MCP Reports", email: "mcp_reports@example.com", password: "password123")
    @expense_category = Category.create!(name: "Transporte Reportes", is_default: true, category_type: "expense")
    @income_category = Category.create!(name: "Salario Reportes", is_default: true, category_type: "income")
    @account = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 10_000_000)

    Expense.create!(user: @user, category: @expense_category, money_source: @account, amount: 100_000,
                    date: Date.current, description: "Gasolina")
    Expense.create!(user: @user, category: @expense_category, money_source: @account, amount: 50_000,
                    date: Date.current - 1.day, description: "Peaje")
    Income.create!(user: @user, category: @income_category, money_source: @account, amount: 3_000_000,
                   date: Date.current, description: "Salario")
  end

  test "monthly report summarizes income, expenses and net cash flow" do
    payload = invoke_tool(Mcp::Tools::Reports::GetMonthlyReportTool, user: @user)

    assert_equal true, payload["success"]
    data = payload["data"]
    assert_equal Date.current.beginning_of_month.iso8601, data.dig("period", "start_date")
    assert_equal Date.current.end_of_month.iso8601, data.dig("period", "end_date")
    assert_equal "3000000.0", data.dig("income", "total")
    assert_equal "150000.0", data.dig("expenses", "total")
    assert_equal "2850000.0", data["net_cash_flow"]
  end

  test "monthly report accepts an explicit month" do
    payload = invoke_tool(Mcp::Tools::Reports::GetMonthlyReportTool, user: @user, month: "2026-09")

    assert_equal "0.0", payload.dig("data", "income", "total")
    assert_equal "2026-09-01", payload.dig("data", "period", "start_date")
  end

  test "expenses by category groups spending without leaking internal scopes" do
    payload = invoke_tool(Mcp::Tools::Reports::GetExpensesByCategoryTool, user: @user)
    data = payload["data"]

    assert_equal "150000.0", data["total"]
    row = data["categories"].first
    assert_equal @expense_category.id, row["id"]
    assert_equal "150000.0", row["total"]
    assert_equal 2, row["count"]
    assert_not row.key?("scope")
  end

  test "income versus expenses returns both totals" do
    payload = invoke_tool(Mcp::Tools::Reports::GetIncomeVsExpensesTool, user: @user)
    data = payload["data"]

    assert_equal "3000000.0", data["income_total"]
    assert_equal "150000.0", data["expenses_total"]
    assert_equal "2850000.0", data["net_cash_flow"]
  end

  test "rejects an inverted custom range" do
    payload = invoke_tool(Mcp::Tools::Reports::GetMonthlyReportTool, user: @user,
                          start_date: Date.current.iso8601, end_date: (Date.current - 3.days).iso8601)

    assert_equal false, payload["success"]
    assert_equal "INVALID_DATE_RANGE", payload.dig("error", "code")
  end
end
