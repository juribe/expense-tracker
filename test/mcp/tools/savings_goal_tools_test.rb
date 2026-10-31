# frozen_string_literal: true

require "test_helper"
require_relative "../../support/mcp_tool_helper"

class SavingsGoalToolsTest < ActiveSupport::TestCase
  include McpToolHelper

  setup do
    @user = User.create!(name: "MCP Goals", email: "mcp_goals@example.com", password: "password123")
    @other_user = User.create!(name: "Other", email: "mcp_goals_other@example.com", password: "password123")
    @pocket = @user.money_sources.create!(name: "Ahorros Meta", kind: "pocket", starting_balance: 500_000)
    @goal = Goal.create!(user: @user, pocket: @pocket, name: "Viaje", target_amount: 1_000_000,
                         target_date: Date.current + 6.months, category: "travel")
    GoalAllocation.create!(financial_goal: @goal, amount: 200_000, date: Date.current)
    @archived = Goal.create!(user: @user, pocket: @pocket, name: "Vieja", target_amount: 100_000,
                             status: "archived")
    @foreign_pocket = @other_user.money_sources.create!(name: "Bolsa Ajena", kind: "pocket", starting_balance: 100)
    @foreign_goal = Goal.create!(user: @other_user, pocket: @foreign_pocket, name: "Ajena", target_amount: 100)
  end

  test "lists active goals with progress and remaining amount" do
    payload = invoke_tool(Mcp::Tools::SavingsGoals::GetSavingsGoalsTool, user: @user)
    goals = payload.dig("data", "savings_goals")
    goal = goals.find { |row| row["id"] == @goal.id }

    assert_equal "1000000.0", goal["target_amount"]
    assert_equal "200000.0", goal["saved_amount"]
    assert_equal "800000.0", goal["remaining_amount"]
    assert_equal 20.0, goal["progress_percentage"]
    assert_not_includes goals.map { |row| row["id"] }, @archived.id
  end

  test "includes archived goals when requested" do
    payload = invoke_tool(Mcp::Tools::SavingsGoals::GetSavingsGoalsTool, user: @user, status: "all")

    assert_includes payload.dig("data", "savings_goals").map { |row| row["id"] }, @archived.id
  end

  test "returns goal details with its pocket" do
    payload = invoke_tool(Mcp::Tools::SavingsGoals::GetSavingsGoalDetailsTool, user: @user, goal_id: @goal.id)

    assert_equal @pocket.id, payload.dig("data", "pocket", "id")
    assert_equal "travel", payload.dig("data", "category")
    assert_equal "200000.0", payload.dig("data", "saved_amount")
  end

  test "does not find another user's goal" do
    payload = invoke_tool(Mcp::Tools::SavingsGoals::GetSavingsGoalDetailsTool, user: @user,
                          goal_id: @foreign_goal.id)

    assert_equal false, payload["success"]
    assert_equal "NOT_FOUND", payload.dig("error", "code")
  end
end
