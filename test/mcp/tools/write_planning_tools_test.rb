# frozen_string_literal: true

require "test_helper"
require_relative "../../support/mcp_tool_helper"

class WritePlanningToolsTest < ActiveSupport::TestCase
  include McpToolHelper

  setup do
    @user = User.create!(name: "MCP Planning", email: "mcp_planning@example.com", password: "password123")
    @other_user = User.create!(name: "Other", email: "mcp_planning_other@example.com", password: "password123")
    @category = Category.create!(name: "Transporte Plan", is_default: true, category_type: "expense")
    @account = @user.money_sources.create!(name: "Ahorros", kind: "account", starting_balance: 1_000_000)
    @pocket = @user.money_sources.create!(name: "Metas", kind: "pocket", starting_balance: 500_000)
    @foreign_pocket = @other_user.money_sources.create!(name: "Ajena", kind: "pocket", starting_balance: 100)
    @foreign_goal = Goal.create!(user: @other_user, pocket: @foreign_pocket, name: "Ajena", target_amount: 100)
  end

  test "creates and updates a budget" do
    payload = invoke_tool(Mcp::Tools::Budgets::CreateBudgetTool, user: @user,
                          category_id: @category.id, amount: "800000")
    assert_equal true, payload["success"]
    budget = Budget.find(payload.dig("data", "id"))
    assert_equal BigDecimal("800000"), budget.monthly_amount
    assert_equal "monthly", budget.period

    payload = invoke_tool(Mcp::Tools::Budgets::UpdateBudgetTool, user: @user,
                          budget_id: budget.id, amount: "900000", active: false)
    assert_equal true, payload["success"]
    assert_equal BigDecimal("900000"), budget.reload.monthly_amount
    assert_not budget.active?
  end

  test "rejects a duplicate budget for the same category" do
    Budget.create!(user: @user, category: @category, monthly_amount: 100_000)

    assert_no_difference "Budget.count" do
      payload = invoke_tool(Mcp::Tools::Budgets::CreateBudgetTool, user: @user,
                            category_id: @category.id, amount: "800000")

      assert_equal false, payload["success"]
      assert_equal "INVALID_ARGUMENT", payload.dig("error", "code")
    end
  end

  test "creates a savings goal inside a pocket" do
    payload = invoke_tool(Mcp::Tools::SavingsGoals::CreateSavingsGoalTool, user: @user,
                          name: "Viaje", target_amount: "2000000",
                          target_date: (Date.current + 6.months).iso8601,
                          pocket_id: @pocket.id, category: "travel")

    assert_equal true, payload["success"]
    goal = Goal.find(payload.dig("data", "id"))
    assert_equal @pocket.id, goal.pocket_id
    assert_equal "0.0", payload.dig("data", "saved_amount")
  end

  test "contributes with a source by moving money into the pocket and reserving it" do
    goal = Goal.create!(user: @user, pocket: @pocket, name: "Viaje", target_amount: 2_000_000)

    payload = invoke_tool(Mcp::Tools::SavingsGoals::ContributeToSavingsGoalTool, user: @user,
                          goal_id: goal.id, amount: "200000", date: Date.current.iso8601,
                          source_id: @account.id)

    assert_equal true, payload["success"]
    assert_equal BigDecimal("700000"), @pocket.reload.balance
    assert_equal BigDecimal("800000"), @account.reload.balance
    assert_equal BigDecimal("200000"), goal.reload.saved_amount
  end

  test "contributes from the pocket without moving money when no source is given" do
    goal = Goal.create!(user: @user, pocket: @pocket, name: "Viaje", target_amount: 2_000_000)

    payload = invoke_tool(Mcp::Tools::SavingsGoals::ContributeToSavingsGoalTool, user: @user,
                          goal_id: goal.id, amount: "100000", date: Date.current.iso8601)

    assert_equal true, payload["success"]
    assert_equal BigDecimal("500000"), @pocket.reload.balance
    assert_equal BigDecimal("100000"), goal.reload.saved_amount
  end

  test "rejects a contribution above the pocket's unallocated money" do
    goal = Goal.create!(user: @user, pocket: @pocket, name: "Viaje", target_amount: 2_000_000)

    assert_no_difference "GoalAllocation.count" do
      payload = invoke_tool(Mcp::Tools::SavingsGoals::ContributeToSavingsGoalTool, user: @user,
                            goal_id: goal.id, amount: "900000", date: Date.current.iso8601)

      assert_equal false, payload["success"]
      assert_equal "INVALID_ARGUMENT", payload.dig("error", "code")
    end
  end

  test "withdraws a goal reservation without moving pocket money" do
    goal = Goal.create!(user: @user, pocket: @pocket, name: "Viaje", target_amount: 2_000_000)
    GoalAllocation.create!(financial_goal: goal, amount: 300_000, date: Date.current)

    payload = invoke_tool(Mcp::Tools::SavingsGoals::WithdrawFromSavingsGoalTool, user: @user,
                          goal_id: goal.id, amount: "100000", date: Date.current.iso8601)

    assert_equal true, payload["success"]
    assert_equal BigDecimal("200000"), goal.reload.saved_amount
    assert_equal BigDecimal("500000"), @pocket.reload.balance
  end

  test "updates a savings goal" do
    goal = Goal.create!(user: @user, pocket: @pocket, name: "Viaje", target_amount: 2_000_000)

    payload = invoke_tool(Mcp::Tools::SavingsGoals::UpdateSavingsGoalTool, user: @user,
                          goal_id: goal.id, name: "Viaje largo", target_amount: "3000000",
                          status: "archived")

    assert_equal true, payload["success"]
    assert_equal "Viaje largo", goal.reload.name
    assert_equal BigDecimal("3000000"), goal.target_amount
    assert goal.archived?
  end

  test "does not update another user's goal" do
    payload = invoke_tool(Mcp::Tools::SavingsGoals::UpdateSavingsGoalTool, user: @user,
                          goal_id: @foreign_goal.id, name: "Hack")

    assert_equal false, payload["success"]
    assert_equal "NOT_FOUND", payload.dig("error", "code")
  end

  test "is idempotent for a goal contribution" do
    goal = Goal.create!(user: @user, pocket: @pocket, name: "Viaje", target_amount: 2_000_000)
    key = SecureRandom.uuid
    arguments = { goal_id: goal.id, amount: "100000", date: Date.current.iso8601,
                  source_id: @account.id, idempotency_key: key }

    first = invoke_tool(Mcp::Tools::SavingsGoals::ContributeToSavingsGoalTool, user: @user, **arguments)
    assert_equal true, first["success"]

    assert_no_difference [ "GoalAllocation.count", "Transfer.count" ] do
      second = invoke_tool(Mcp::Tools::SavingsGoals::ContributeToSavingsGoalTool, user: @user, **arguments)
      assert_equal first.dig("data", "id"), second.dig("data", "id")
    end
  end
end
