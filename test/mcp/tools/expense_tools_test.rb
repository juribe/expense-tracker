# frozen_string_literal: true

require "test_helper"
require_relative "../../support/mcp_tool_helper"

class ExpenseToolsTest < ActiveSupport::TestCase
  include McpToolHelper

  setup do
    @user = User.create!(name: "MCP Expenses", email: "mcp_expenses@example.com", password: "password123")
    @other_user = User.create!(name: "Other", email: "mcp_expenses_other@example.com", password: "password123")
    @category = Category.create!(name: "Transporte Gastos", is_default: true, category_type: "expense")
    @other_category = Category.create!(name: "Comida Gastos", is_default: true, category_type: "expense")
    @account = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 5_000_000)
    @other_account = @other_user.money_sources.create!(name: "Cuenta Ajena", kind: "account", starting_balance: 1_000_000)

    @gasolina = Expense.create!(user: @user, category: @category, money_source: @account,
                                amount: 100_000, date: Date.current, description: "Gasolina")
    @taxi = Expense.create!(user: @user, category: @other_category, money_source: @account,
                            amount: 50_000, date: Date.current - 1.day, description: "Taxi")
    @old_expense = Expense.create!(user: @user, category: @category, money_source: @account,
                                   amount: 70_000, date: Date.current - 2.months, description: "Viejo")
    @foreign_expense = Expense.create!(user: @other_user, category: @category, money_source: @other_account,
                                       amount: 10_000, date: Date.current, description: "Ajena")
  end

  test "lists the current period newest first" do
    payload = invoke_tool(Mcp::Tools::Expenses::GetExpensesTool, user: @user)

    assert_equal true, payload["success"]
    ids = payload.dig("data", "expenses").map { |expense| expense["id"] }
    assert_equal [ @gasolina.id, @taxi.id ], ids
    assert_not_includes ids, @old_expense.id
    assert_not_includes ids, @foreign_expense.id
  end

  test "paginates with limit and offset" do
    payload = invoke_tool(Mcp::Tools::Expenses::GetExpensesTool, user: @user, limit: 1)

    pagination = payload.dig("data", "pagination")
    assert_equal 1, payload.dig("data", "expenses").size
    assert_equal 2, pagination["total"]
    assert_equal true, pagination["has_more"]
    assert_equal 1, pagination["next_offset"]
  end

  test "filters by category and money source" do
    payload = invoke_tool(Mcp::Tools::Expenses::GetExpensesTool, user: @user, category_id: @category.id)

    assert_equal [ @gasolina.id ], payload.dig("data", "expenses").map { |expense| expense["id"] }

    payload = invoke_tool(Mcp::Tools::Expenses::GetExpensesTool, user: @user, money_source_id: @account.id)
    assert_equal 2, payload.dig("data", "expenses").size
  end

  test "returns amounts as positive decimal strings with references" do
    payload = invoke_tool(Mcp::Tools::Expenses::GetExpenseTool, user: @user, expense_id: @gasolina.id)
    expense = payload["data"]

    assert_equal "100000.0", expense["amount"]
    assert_equal "expense", expense["kind"]
    assert_equal @category.id, expense.dig("category", "id")
    assert_equal @account.id, expense.dig("money_source", "id")
    assert_equal "Gasolina", expense["description"]
  end

  test "rejects an invalid date range" do
    payload = invoke_tool(Mcp::Tools::Expenses::GetExpensesTool, user: @user, start_date: "not-a-date")

    assert_equal false, payload["success"]
    assert_equal "INVALID_DATE_RANGE", payload.dig("error", "code")
  end

  test "rejects a start date after the end date" do
    payload = invoke_tool(Mcp::Tools::Expenses::GetExpensesTool, user: @user,
                          start_date: Date.current.iso8601, end_date: (Date.current - 2.days).iso8601)

    assert_equal false, payload["success"]
    assert_equal "INVALID_DATE_RANGE", payload.dig("error", "code")
  end

  test "rejects a category of another user" do
    payload = invoke_tool(Mcp::Tools::Expenses::GetExpensesTool, user: @user,
                          category_id: Category.create!(name: "Privada", user: @other_user, category_type: "expense").id)

    assert_equal false, payload["success"]
    assert_equal "INVALID_CATEGORY", payload.dig("error", "code")
  end

  test "does not find another user's expense" do
    payload = invoke_tool(Mcp::Tools::Expenses::GetExpenseTool, user: @user, expense_id: @foreign_expense.id)

    assert_equal false, payload["success"]
    assert_equal "NOT_FOUND", payload.dig("error", "code")
  end

  test "rejects a limit above the maximum" do
    payload = invoke_tool(Mcp::Tools::Expenses::GetExpensesTool, user: @user, limit: 101)

    assert_equal false, payload["success"]
    assert_equal "INVALID_ARGUMENT", payload.dig("error", "code")
  end
end
