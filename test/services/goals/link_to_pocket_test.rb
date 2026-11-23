# frozen_string_literal: true

require "test_helper"

module Goals
  class LinkToPocketTest < ActiveSupport::TestCase
    setup do
      @user = simple_user
      @goal = Goal.create!(user: @user, name: "Vacaciones", target_amount: 5_000_000)
      @allocation = @goal.goal_allocations.create!(amount: 2_000_000, date: Date.current, note: "Ahorro virtual")
    end

    test "links a virtual goal to a pocket with enough unallocated balance" do
      pocket = @user.money_sources.create!(name: "Ahorros", kind: "pocket", starting_balance: 2_000_000)

      assert_no_difference "GoalAllocation.count" do
        result = LinkToPocket.call(goal: @goal, pocket: pocket, user: @user)
        assert result.success?, "error=#{result.error.inspect}"
      end

      @goal.reload
      assert_equal pocket.id, @goal.pocket_id
      refute @goal.virtual?
      assert_equal 2_000_000, @goal.saved_amount
      assert_equal pocket.id, @allocation.reload.pocket_id
      assert_equal 2_000_000, pocket.reload.allocated_amount
      assert_equal 0, pocket.unallocated_amount
      assert_equal "Ahorro virtual", @allocation.note
      assert_equal Date.current, @allocation.date
    end

    test "rejects a pocket without enough unallocated balance" do
      pocket = @user.money_sources.create!(name: "Ahorros", kind: "pocket", starting_balance: 1_000_000)

      result = LinkToPocket.call(goal: @goal, pocket: pocket, user: @user)

      refute result.success?
      assert_equal :insufficient_pocket_balance, result.error
      assert @goal.reload.virtual?
      assert_nil @allocation.reload.pocket_id
      assert_equal 0, pocket.reload.allocated_amount
    end

    test "rejects a pocket owned by another user" do
      other = User.create!(name: "Other", email: "link_other_#{SecureRandom.hex(4)}@example.com",
                           password: "password123")
      foreign = other.money_sources.create!(name: "Ajena", kind: "pocket", starting_balance: 5_000_000)

      result = LinkToPocket.call(goal: @goal, pocket: foreign, user: @user)

      refute result.success?
      assert_equal :not_owner, result.error
      assert @goal.reload.virtual?
    end

    test "linking a goal that already has a pocket is a no-op" do
      pocket = @user.money_sources.create!(name: "Ahorros", kind: "pocket", starting_balance: 2_000_000)
      LinkToPocket.call(goal: @goal, pocket: pocket, user: @user)

      result = LinkToPocket.call(goal: @goal, pocket: pocket, user: @user)

      assert result.success?
      assert_equal 1, @goal.reload.goal_allocations.count
      assert_equal pocket.id, @goal.pocket_id
    end

    private

    def simple_user
      User.create!(name: "Link Simple", email: "link_simple_#{SecureRandom.hex(4)}@example.com",
                   password: "password123").tap do |user|
        user.update!(money_tracking_mode: "simple", money_tracking_mode_selected_at: Time.current)
      end
    end
  end
end
