# frozen_string_literal: true

require "test_helper"

class GoalAllocationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Test User",
      email: "goal_allocations_test@example.com",
      password: "password123"
    )
    @pocket = MoneySource.create!(user: @user, name: "Ahorros", kind: "pocket", starting_balance: 1_000_000)
    @goal = Goal.create!(user: @user, pocket: @pocket, name: "Viaje Europa", target_amount: 20_000_000)
    sign_in @user
  end

  test "POST /goal_allocations assigns pocket money to the goal" do
    assert_difference("GoalAllocation.count", 1) do
      post goal_allocations_path, params: { goal_allocations: {
        financial_goal_id: @goal.id, amount: "500.000", date: Date.current.to_s
      } }
    end
    allocation = GoalAllocation.last
    assert_equal @goal, allocation.financial_goal
    assert_equal @pocket, allocation.pocket
    assert_equal 500_000, allocation.amount
    assert_equal 500_000, @goal.reload.saved_amount.to_i
    assert_redirected_to goals_path
  end

  test "POST /goal_allocations never touches expenses, income or balances" do
    balance = @pocket.balance
    assert_difference("GoalAllocation.count", 1) do
      post goal_allocations_path, params: { goal_allocations: { financial_goal_id: @goal.id, amount: "250.000", date: Date.current.to_s } }
    end
    assert_equal balance, @pocket.reload.balance
    assert_equal 0, Expense.count
    assert_equal 0, Income.count
    assert_equal 0, Transfer.count
  end

  test "POST /goal_allocations accepts the goal_allocation param naming too" do
    assert_difference("GoalAllocation.count", 1) do
      post goal_allocations_path, params: { goal_allocation: {
        financial_goal_id: @goal.id, amount: "300.000", date: Date.current.to_s
      } }
    end
    assert_equal 300_000, @goal.reload.saved_amount.to_i
  end

  test "POST /goal_allocations rejects overallocation" do
    assert_no_difference("GoalAllocation.count") do
      post goal_allocations_path, params: { goal_allocations: {
        financial_goal_id: @goal.id, amount: "2.000.000", date: Date.current.to_s
      } }
    end
    # After assigning the whole balance (1M), nothing more fits.
    post goal_allocations_path, params: { goal_allocations: { financial_goal_id: @goal.id, amount: "1.000.000", date: Date.current.to_s } }
    assert_no_difference("GoalAllocation.count") do
      post goal_allocations_path, params: { goal_allocations: {
        financial_goal_id: @goal.id, amount: "100.000", date: Date.current.to_s
      } }
    end
  end

  test "POST /goal_allocations with a negative amount releases the reservation" do
    @goal.goal_allocations.create!(pocket: @pocket, amount: 600_000, date: Date.current)
    assert_difference("GoalAllocation.count", 1) do
      post goal_allocations_path, params: { goal_allocations: {
        financial_goal_id: @goal.id, amount: "-200.000", date: Date.current.to_s
      } }
    end
    assert_equal 400_000, @goal.reload.saved_amount.to_i
    # Balance 1M minus the 400k still reserved for the goal.
    assert_equal 600_000, @pocket.reload.unallocated_amount.to_i
  end

  test "POST /goal_allocations/reallocate moves the reservation between goals" do
    other = Goal.create!(user: @user, pocket: @pocket, name: "Carro", target_amount: 30_000_000)
    @goal.goal_allocations.create!(pocket: @pocket, amount: 600_000, date: Date.current)

    assert_difference("GoalAllocation.count", 2) do
      post reallocate_goal_allocations_path, params: { from_goal_id: @goal.id, to_goal_id: other.id, amount: "200.000" }
    end
    assert_equal 400_000, @goal.reload.saved_amount.to_i
    assert_equal 200_000, other.reload.saved_amount.to_i
    # The pocket total is untouched by reallocations.
    assert_equal 1_000_000, @pocket.reload.balance.to_i
  end

  test "POST /goal_allocations/reallocate rejects cross-pocket goals" do
    other_pocket = MoneySource.create!(user: @user, name: "Otro", kind: "pocket", starting_balance: 0)
    other_goal = Goal.create!(user: @user, pocket: other_pocket, name: "Carro", target_amount: 5_000_000)

    assert_no_difference("GoalAllocation.count") do
      post reallocate_goal_allocations_path, params: { from_goal_id: @goal.id, to_goal_id: other_goal.id, amount: "100.000" }
    end
  end

  test "DELETE /goal_allocations/:id removes the reservation back to unallocated" do
    allocation = @goal.goal_allocations.create!(pocket: @pocket, amount: 300_000, date: Date.current)
    assert_difference("GoalAllocation.count", -1) do
      delete goal_allocation_path(allocation)
    end
    assert_equal 0, @goal.reload.saved_amount.to_i
    assert_equal 1_000_000, @pocket.reload.unallocated_amount.to_i
  end

  test "other users' goals and allocations are not reachable" do
    other_user = User.create!(name: "Other", email: "other_alloc@example.com", password: "password123")
    other_pocket = MoneySource.create!(user: other_user, name: "Ajeno", kind: "pocket", starting_balance: 100)
    other_goal = Goal.create!(user: other_user, pocket: other_pocket, name: "Ajena", target_amount: 1_000_000)
    other_allocation = other_goal.goal_allocations.create!(pocket: other_pocket, amount: 100, date: Date.current)

    assert_no_difference("GoalAllocation.count") do
      post goal_allocations_path, params: { goal_allocations: { financial_goal_id: other_goal.id, amount: "50.000", date: Date.current.to_s } }
    end

    assert_no_difference("GoalAllocation.count") do
      delete goal_allocation_path(other_allocation)
    end
  end
end
