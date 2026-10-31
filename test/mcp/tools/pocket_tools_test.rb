# frozen_string_literal: true

require "test_helper"
require_relative "../../support/mcp_tool_helper"

class PocketToolsTest < ActiveSupport::TestCase
  include McpToolHelper

  setup do
    @user = User.create!(name: "MCP Pockets", email: "mcp_pockets@example.com", password: "password123")
    @other_user = User.create!(name: "Other", email: "mcp_pockets_other@example.com", password: "password123")
    @pocket = @user.money_sources.create!(name: "Vacaciones", kind: "pocket", starting_balance: 500_000)
    @goal = Goal.create!(user: @user, pocket: @pocket, name: "Viaje", target_amount: 1_000_000)
    GoalAllocation.create!(financial_goal: @goal, amount: 200_000, date: Date.current)
    @foreign_pocket = @other_user.money_sources.create!(name: "Ajena", kind: "pocket", starting_balance: 100)
  end

  test "lists pockets with allocated and unallocated money" do
    payload = invoke_tool(Mcp::Tools::Pockets::GetPocketsTool, user: @user)
    pocket = payload.dig("data", "pockets").find { |row| row["id"] == @pocket.id }

    assert_equal "500000.0", pocket["balance"]
    assert_equal "200000.0", pocket["allocated_amount"]
    assert_equal "300000.0", pocket["unallocated_amount"]
  end

  test "returns pocket details with its goals" do
    payload = invoke_tool(Mcp::Tools::Pockets::GetPocketDetailsTool, user: @user, pocket_id: @pocket.id)

    assert_equal "500000.0", payload.dig("data", "balance")
    goal = payload.dig("data", "goals").first
    assert_equal @goal.id, goal["id"]
    assert_equal "200000.0", goal["saved_amount"]
  end

  test "rejects a source that is not a pocket" do
    account = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 100)

    payload = invoke_tool(Mcp::Tools::Pockets::GetPocketDetailsTool, user: @user, pocket_id: account.id)

    assert_equal false, payload["success"]
    assert_equal "INVALID_POCKET", payload.dig("error", "code")
  end

  test "does not find another user's pocket" do
    payload = invoke_tool(Mcp::Tools::Pockets::GetPocketDetailsTool, user: @user, pocket_id: @foreign_pocket.id)

    assert_equal false, payload["success"]
    assert_equal "NOT_FOUND", payload.dig("error", "code")
  end
end
