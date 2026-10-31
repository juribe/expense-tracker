# frozen_string_literal: true

require "test_helper"
require_relative "../../support/mcp_tool_helper"

class McpSecurityTest < ActiveSupport::TestCase
  include McpToolHelper

  setup do
    @user = User.create!(name: "MCP Security", email: "mcp_security@example.com", password: "password123")
    @other_user = User.create!(name: "Other", email: "mcp_security_other@example.com", password: "password123")
    @category = Category.create!(name: "Seguridad", is_default: true, category_type: "expense")
    @account = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 1_000_000)
    @foreign_category = Category.create!(name: "Privada", user: @other_user, category_type: "expense")
  end

  test "no tool schema exposes user_id" do
    tools = Mcp::ServerFactory.build(scopes: %w[read write]).tools.values

    assert tools.any?
    tools.each do |tool|
      schema = tool.input_schema_to_json || {}
      properties = schema[:properties] || schema["properties"] || {}
      assert_not properties.key?(:user_id), "#{tool.tool_name} exposes user_id"
      assert_not properties.key?("user_id"), "#{tool.tool_name} exposes user_id"
    end
  end

  test "a failed write is audited with its stable error code" do
    invoke_tool(Mcp::Tools::Expenses::CreateExpenseTool, user: @user,
                amount: "1000", date: Date.current.iso8601,
                category_id: @foreign_category.id, money_source_id: @account.id, description: "X")

    audit = McpToolInvocation.where(tool_name: "create_expense").last
    assert_equal "failed", audit.status
    assert_equal "INVALID_CATEGORY", audit.error_code
    assert_nil audit.resource_id
  end

  test "read tools are not audited" do
    assert_no_difference "McpToolInvocation.count" do
      invoke_tool(Mcp::Tools::Context::GetMoneySourcesTool, user: @user)
    end
  end

  test "the authenticated user can only reach their own records" do
    foreign = Expense.create!(
      user: @other_user, category: @foreign_category,
      money_source: @other_user.money_sources.create!(name: "Ajena", kind: "account", starting_balance: 10_000),
      amount: 1000, date: Date.current, description: "Ajena"
    )

    payload = invoke_tool(Mcp::Tools::Expenses::GetExpenseTool, user: @user, expense_id: foreign.id)
    assert_equal "NOT_FOUND", payload.dig("error", "code")
  end
end
