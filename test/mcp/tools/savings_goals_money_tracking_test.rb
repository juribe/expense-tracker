# frozen_string_literal: true

require "test_helper"
require_relative "../../support/mcp_tool_helper"

class SavingsGoalsMoneyTrackingTest < ActiveSupport::TestCase
  include McpToolHelper

  setup do
    @user = User.create!(name: "MCP Simple Goals", email: "mcp_simple_goals_#{SecureRandom.hex(4)}@example.com",
                         password: "password123")
    @user.update!(money_tracking_mode: "simple", money_tracking_mode_selected_at: Time.current)
  end

  test "creates a virtual goal without a pocket in simple mode" do
    payload = invoke_tool(
      Mcp::Tools::SavingsGoals::CreateSavingsGoalTool,
      user: @user,
      name: "Vacaciones",
      target_amount: "5000000"
    )

    assert_equal true, payload["success"]
    goal = Goal.find(payload.dig("data", "id"))
    assert_nil goal.pocket_id
    assert goal.virtual?
    assert_equal "virtual", payload.dig("data", "funding")
  end

  test "contributes to and withdraws from a virtual goal without a source" do
    goal = Goal.create!(user: @user, name: "Vacaciones", target_amount: 5_000_000)

    contribution = invoke_tool(
      Mcp::Tools::SavingsGoals::ContributeToSavingsGoalTool,
      user: @user,
      goal_id: goal.id,
      amount: "300000",
      date: Date.current.iso8601
    )
    assert_equal true, contribution["success"]
    assert_equal "300000.0", contribution.dig("data", "goal", "saved_amount")

    withdrawal = invoke_tool(
      Mcp::Tools::SavingsGoals::WithdrawFromSavingsGoalTool,
      user: @user,
      goal_id: goal.id,
      amount: "100000",
      date: Date.current.iso8601
    )
    assert_equal true, withdrawal["success"]
    assert_equal "200000.0", withdrawal.dig("data", "goal", "saved_amount")
    assert_equal 200_000, goal.reload.saved_amount
  end

  test "advanced mode still requires a pocket when creating a goal" do
    detailed = User.create!(name: "MCP Advanced Goals",
                            email: "mcp_advanced_goals_#{SecureRandom.hex(4)}@example.com",
                            password: "password123")

    payload = invoke_tool(
      Mcp::Tools::SavingsGoals::CreateSavingsGoalTool,
      user: detailed,
      name: "Vacaciones",
      target_amount: "5000000"
    )

    assert_equal false, payload["success"]
    assert_equal "INVALID_ARGUMENT", payload.dig("error", "code")
  end
end
