# frozen_string_literal: true

require "test_helper"

class GoalAllocationsReallocateTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Test User", email: "reallocate_test@example.com", password: "password123")
    @pocket = @user.money_sources.create!(name: "Ahorros", kind: "pocket", starting_balance: 10_000_000)
    @travel = Goal.create!(user: @user, pocket: @pocket, name: "Viaje Europa", target_amount: 20_000_000)
    @car = Goal.create!(user: @user, pocket: @pocket, name: "Carro", target_amount: 30_000_000)
    @travel.goal_allocations.create!(pocket: @pocket, amount: 2_500_000, date: Date.today)
    @car.goal_allocations.create!(pocket: @pocket, amount: 2_500_000, date: Date.today)
  end

  test "moves the reservation between goals of the same pocket" do
    result = GoalAllocations::Reallocate.call(goal_from: @travel, goal_to: @car, amount: 500_000, user: @user)

    assert result[:ok]
    assert_equal 2_000_000, @travel.reload.saved_amount
    assert_equal 3_000_000, @car.reload.saved_amount
    # The pocket keeps everything: reservation, not movement.
    assert_equal 10_000_000, @pocket.reload.balance.to_i
    assert_equal 5_000_000, @pocket.reload.allocated_amount.to_i
  end

  test "writes compensating allocation records for audit" do
    GoalAllocations::Reallocate.call(goal_from: @travel, goal_to: @car, amount: 500_000, user: @user)

    latest = @travel.reload.goal_allocations.order(:created_at).last
    assert_equal(-500_000, latest.amount)
    latest_car = @car.reload.goal_allocations.order(:created_at).last
    assert_equal 500_000, latest_car.amount
  end

  test "rejects goals from different pockets" do
    other_pocket = @user.money_sources.create!(name: "Otro", kind: "pocket", starting_balance: 5_000_000)
    other_goal = Goal.create!(user: @user, pocket: other_pocket, name: "Universidad", target_amount: 8_000_000)

    result = GoalAllocations::Reallocate.call(goal_from: @travel, goal_to: other_goal, amount: 100_000, user: @user)
    assert_not result[:ok]
    assert_equal :different_pockets, result[:error]
  end

  test "rejects the same goal on both ends" do
    result = GoalAllocations::Reallocate.call(goal_from: @travel, goal_to: @travel, amount: 100_000, user: @user)
    assert_not result[:ok]
    assert_equal :same_goal, result[:error]
  end

  test "rejects zero or negative amounts" do
    assert_equal :invalid_amount, GoalAllocations::Reallocate.call(goal_from: @travel, goal_to: @car, amount: 0, user: @user)[:error]
    assert_equal :invalid_amount, GoalAllocations::Reallocate.call(goal_from: @travel, goal_to: @car, amount: -100, user: @user)[:error]
  end

  test "rejects users who do not own the goals" do
    other_user = User.create!(name: "Other", email: "reallocate_other@example.com", password: "password123")
    result = GoalAllocations::Reallocate.call(goal_from: @travel, goal_to: @car, amount: 100_000, user: other_user)
    assert_not result[:ok]
    assert_equal :not_owner, result[:error]
  end

  test "rejects amounts beyond the origin goal's saved amount" do
    GoalAllocations::Reallocate.call(goal_from: @travel, goal_to: @car, amount: 3_000_000, user: @user)

    # Both writes rolled back atomically.
    assert_equal 2_500_000, @travel.reload.saved_amount
    assert_equal 2_500_000, @car.reload.saved_amount
  end
end
