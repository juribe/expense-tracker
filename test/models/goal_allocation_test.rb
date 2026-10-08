# frozen_string_literal: true

require "test_helper"

class GoalAllocationTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Test User", email: "allocation_test@example.com", password: "password123")
    @pocket = @user.money_sources.create!(name: "Ahorros", kind: "pocket", starting_balance: 6_000_000)
    @goal = Goal.create!(user: @user, pocket: @pocket, name: "Viaje Europa", target_amount: 20_000_000)
  end

  def create_allocation(**overrides)
    GoalAllocation.create!(
      { financial_goal: @goal, pocket: @pocket, amount: 1_000_000, date: Date.today }.merge(overrides)
    )
  end

  test "is valid with goal, pocket and a nonzero amount" do
    assert create_allocation.valid?
  end

  test "amount cannot be zero" do
    allocation = GoalAllocation.new(financial_goal: @goal, pocket: @pocket, amount: 0, date: Date.today)
    assert_not allocation.valid?
    assert_includes allocation.errors[:amount], I18n.t("errors.messages.other_than", count: 0)
  end

  test "amount is required" do
    allocation = GoalAllocation.new(financial_goal: @goal, pocket: @pocket, date: Date.today)
    assert_not allocation.valid?
    assert_includes allocation.errors[:amount], I18n.t("errors.messages.blank")
  end

  test "date is required" do
    allocation = GoalAllocation.new(financial_goal: @goal, pocket: @pocket, amount: 100)
    assert_not allocation.valid?
    assert_includes allocation.errors[:date], I18n.t("errors.messages.blank")
  end

  test "pocket must be the goal's pocket" do
    other_pocket = @user.money_sources.create!(name: "Otro bolsillo", kind: "pocket", starting_balance: 0)
    allocation = GoalAllocation.new(financial_goal: @goal, pocket: other_pocket, amount: 100, date: Date.today)
    assert_not allocation.valid?
    assert_includes allocation.errors[:pocket], I18n.t("activerecord.errors.messages.pocket_mismatch")
  end

  test "allocations cannot exceed the pocket's balance" do
    create_allocation(amount: 5_000_000)
    over = GoalAllocation.new(financial_goal: @goal, pocket: @pocket, amount: 2_000_000, date: Date.today)
    assert_not over.valid?
    assert_includes over.errors[:amount], I18n.t("activerecord.errors.messages.pocket_overallocated")
  end

  test "allocations exactly up to the pocket balance are allowed" do
    create_allocation(amount: 6_000_000)
    assert @pocket.reload.unallocated_amount.zero?
  end

  test "a release cannot sink the goal's saved amount below zero" do
    release = GoalAllocation.new(financial_goal: @goal, pocket: @pocket, amount: -1, date: Date.today)
    assert_not release.valid?
    assert_includes release.errors[:amount], I18n.t("activerecord.errors.messages.goal_saved_negative")
  end

  test "releasing reserved money is allowed" do
    create_allocation(amount: 2_000_000)
    release = create_allocation(amount: -500_000)
    assert release.valid?
    assert_equal 1_500_000, @goal.reload.saved_amount
    assert_equal 6_000_000, @pocket.reload.balance
  end

  test "allocations never change the pocket's balance" do
    assert_difference -> { @pocket.reload.balance }, 0 do
      create_allocation(amount: 1_000_000)
    end
    assert_equal 0, Expense.count
    assert_equal 0, Income.count
    assert_equal 0, Transfer.count
  end

  test "es-formatted amounts are normalized" do
    allocation = GoalAllocation.new(financial_goal: @goal, pocket: @pocket, amount: "1.500.000,50", date: Date.today)
    allocation.valid?
    assert_equal 1_500_000.5, allocation.amount
  end

  test "destroying the goal frees its allocations back to unallocated" do
    create_allocation(amount: 2_000_000)
    @goal.destroy
    assert_equal 6_000_000, @pocket.reload.unallocated_amount
  end
end
