# frozen_string_literal: true

require "test_helper"
require_relative "../../support/mcp_tool_helper"

class MoneyTrackingToolsTest < ActiveSupport::TestCase
  include McpToolHelper

  setup do
    @category = Category.create!(name: "MCP Tracking Expense", is_default: true, category_type: "expense")
    @income_category = Category.create!(name: "MCP Tracking Income", is_default: true, category_type: "income")
  end

  test "create_expense without money_source_id uses General in simple mode" do
    user = simple_user
    general = user.general_money_source
    token, = McpAccessToken.issue!(user: user, name: "Simple Writer", scopes: [ :read, :write ])

    payload = invoke_tool(
      Mcp::Tools::Expenses::CreateExpenseTool,
      user: user,
      token: token,
      amount: "30000",
      date: Date.current.iso8601,
      category_id: @category.id,
      description: "Almuerzo"
    )

    assert_equal true, payload["success"]
    expense = Expense.find(payload.dig("data", "id"))
    assert_equal general.id, expense.money_source_id
    assert_equal BigDecimal("-30000"), general.reload.balance
  end

  test "create_income without money_source_id uses General in simple mode" do
    user = simple_user
    general = user.general_money_source
    token, = McpAccessToken.issue!(user: user, name: "Simple Income Writer", scopes: [ :read, :write ])

    payload = invoke_tool(
      Mcp::Tools::Incomes::CreateIncomeTool,
      user: user,
      token: token,
      amount: "100000",
      date: Date.current.iso8601,
      category_id: @income_category.id,
      description: "Ingreso"
    )

    assert_equal true, payload["success"]
    income = Income.find(payload.dig("data", "id"))
    assert_equal general.id, income.money_source_id
    assert_equal BigDecimal("100000"), general.reload.balance
  end

  test "create_expense in advanced mode uses the configured default source" do
    user = detailed_user
    account = user.money_sources.create!(name: "Predeterminada", kind: "account", starting_balance: 1_000_000)
    user.update!(default_money_source: account)

    payload = invoke_tool(
      Mcp::Tools::Expenses::CreateExpenseTool,
      user: user,
      amount: "30000",
      date: Date.current.iso8601,
      category_id: @category.id,
      description: "Almuerzo"
    )

    assert_equal true, payload["success"]
    expense = Expense.find(payload.dig("data", "id"))
    assert_equal account.id, expense.money_source_id
  end

  test "create_expense in advanced mode without a default source still fails" do
    user = detailed_user

    payload = invoke_tool(
      Mcp::Tools::Expenses::CreateExpenseTool,
      user: user,
      amount: "30000",
      date: Date.current.iso8601,
      category_id: @category.id,
      description: "Almuerzo"
    )

    assert_equal false, payload["success"]
    assert_equal "INVALID_ARGUMENT", payload.dig("error", "code")
  end

  private

  def simple_user
    user = User.create!(name: "MCP Simple", email: "mcp_simple_#{SecureRandom.hex(4)}@example.com",
                        password: "password123")
    user.update!(money_tracking_mode: "simple", money_tracking_mode_selected_at: Time.current)
    user.ensure_general_money_source!
    user
  end

  def detailed_user
    User.create!(name: "MCP Advanced", email: "mcp_advanced_#{SecureRandom.hex(4)}@example.com",
                 password: "password123")
  end
end
