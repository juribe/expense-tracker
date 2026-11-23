# frozen_string_literal: true

require "test_helper"

module Goals
  class CompleteTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Complete Goal", email: "complete_goal_#{SecureRandom.hex(4)}@example.com",
                           password: "password123")
      @user.update!(money_tracking_mode: "simple", money_tracking_mode_selected_at: Time.current)
      @goal = Goal.create!(user: @user, name: "Emergencias", target_amount: 1_000_000)
    end

    test "marks a satisfied goal as archived without deleting allocations" do
      @goal.goal_allocations.create!(amount: 1_000_000, date: Date.current, note: "Meta cumplida")

      result = Complete.call(goal: @goal)

      assert result.success?
      assert @goal.reload.archived?
      assert_equal 1, @goal.goal_allocations.count
      assert_equal 1_000_000, @goal.saved_amount
    end

    test "does not complete a goal before reaching its target" do
      @goal.goal_allocations.create!(amount: 100_000, date: Date.current)

      result = Complete.call(goal: @goal)

      refute result.success?
      assert_equal :target_not_reached, result.error
      refute @goal.reload.archived?
    end
  end
end
