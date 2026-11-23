# frozen_string_literal: true

require "test_helper"

class GoalAllocationsMoneyTrackingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = simple_user
    @goal = Goal.create!(user: @user, name: "Vacaciones", target_amount: 5_000_000)
    sign_in @user
  end

  test "adds money to a virtual goal and updates progress" do
    assert_difference "GoalAllocation.count", 1 do
      post goal_allocations_path, params: { goal_allocations: {
        financial_goal_id: @goal.id, amount: "300.000", date: Date.current.to_s,
        direction: "deposit", note: "Aporte"
      } }
    end

    allocation = GoalAllocation.order(:created_at).last
    assert_redirected_to goals_path
    assert_equal 300_000, allocation.amount
    assert_nil allocation.pocket_id
    assert_equal 300_000, @goal.reload.saved_amount
    assert_in_delta 6.0, @goal.progress_percentage, 0.01
  end

  test "withdraws money from a virtual goal" do
    @goal.goal_allocations.create!(amount: 500_000, date: Date.current)

    assert_difference "GoalAllocation.count", 1 do
      post goal_allocations_path, params: { goal_allocations: {
        financial_goal_id: @goal.id, amount: "200.000", date: Date.current.to_s,
        direction: "withdraw", note: "Retiro"
      } }
    end

    assert_equal 300_000, @goal.reload.saved_amount
    assert_equal(-200_000, GoalAllocation.order(:created_at).last.amount)
  end

  test "rejects a withdrawal above the virtual saved amount" do
    @goal.goal_allocations.create!(amount: 100_000, date: Date.current)

    assert_no_difference "GoalAllocation.count" do
      post goal_allocations_path, params: { goal_allocations: {
        financial_goal_id: @goal.id, amount: "200.000", date: Date.current.to_s, direction: "withdraw"
      } }
    end

    assert_redirected_to goals_path
    assert_equal 100_000, @goal.reload.saved_amount
  end

  test "does not change General or create financial movements" do
    general = @user.general_money_source
    balance_before = general.balance
    expense_count = Expense.count
    income_count = Income.count
    transfer_count = Transfer.count

    post goal_allocations_path, params: { goal_allocations: {
      financial_goal_id: @goal.id, amount: "800.000", date: Date.current.to_s, direction: "deposit"
    } }

    assert_equal balance_before, general.reload.balance
    assert_equal expense_count, Expense.count
    assert_equal income_count, Income.count
    assert_equal transfer_count, Transfer.count
  end

  test "repeating the same idempotency key does not duplicate the contribution" do
    key = SecureRandom.uuid
    params = { goal_allocations: {
      financial_goal_id: @goal.id, amount: "100.000", date: Date.current.to_s,
      direction: "deposit", idempotency_key: key
    } }

    assert_difference "GoalAllocation.count", 1 do
      post goal_allocations_path, params: params
      post goal_allocations_path, params: params
    end

    assert_equal 100_000, @goal.reload.saved_amount
  end

  test "history shows contributions and withdrawals with date and amount" do
    @goal.goal_allocations.create!(amount: 300_000, date: Date.current, note: "Aporte historial")
    @goal.goal_allocations.create!(amount: -100_000, date: Date.current, note: "Retiro historial")

    get goals_path

    assert_response :success
    assert_select "[data-testid=goal-history]", text: /Aporte historial/
    assert_select "[data-testid=goal-history]", text: /Retiro historial/
    assert_select "[data-testid=goal-history]", text: /\$300\.000/
    assert_select "[data-testid=goal-history]", text: /\$100\.000/
  end

  private

  def simple_user
    User.create!(name: "Allocations Simple", email: "allocations_simple_#{SecureRandom.hex(4)}@example.com",
                 password: "password123").tap do |user|
      user.update!(money_tracking_mode: "simple", money_tracking_mode_selected_at: Time.current)
    end
  end
end
