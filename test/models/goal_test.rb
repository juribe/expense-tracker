# frozen_string_literal: true

require "test_helper"

class GoalTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Test User", email: "goal_test@example.com", password: "password123")
    @pocket = @user.money_sources.create!(name: "Ahorros", kind: "pocket", starting_balance: 20_000_000)
  end

  def create_pocket(name: "Bolsillo", starting_balance: 0)
    @user.money_sources.create!(name: name, kind: "pocket", starting_balance: starting_balance)
  end

  def allocate(goal, amount, **overrides)
    goal.goal_allocations.create!(
      { pocket: goal.pocket, amount: amount, date: Date.current }.merge(overrides)
    )
  end

  def create_goal(**overrides)
    pocket = overrides.delete(:pocket) || @pocket
    Goal.create!({ user: @user, pocket: pocket, name: "Fondo de emergencia", target_amount: 5_000_000 }.merge(overrides))
  end

  test "is valid with required attributes" do
    goal = Goal.new(user: @user, pocket: @pocket, name: "Viaje", target_amount: 1_000_000)
    assert goal.valid?
  end

  test "name is required" do
    goal = Goal.new(user: @user, pocket: @pocket, target_amount: 1_000_000)
    assert_not goal.valid?
    assert_includes goal.errors[:name], I18n.t("errors.messages.blank")
  end

  test "user is required" do
    goal = Goal.new(name: "Viaje", pocket: @pocket, target_amount: 1_000_000)
    assert_not goal.valid?
    assert goal.errors[:user].any?
  end

  test "target_amount is required and must be positive" do
    goal = Goal.new(user: @user, name: "Viaje", pocket: @pocket)
    assert_not goal.valid?
    assert_includes goal.errors[:target_amount], I18n.t("errors.messages.blank")

    goal.target_amount = 0
    assert_not goal.valid?
    assert_includes goal.errors[:target_amount], I18n.t("errors.messages.greater_than", count: 0)
  end

  test "pocket is required" do
    goal = Goal.new(user: @user, name: "Viaje", target_amount: 1_000_000)
    assert_not goal.valid?
    assert goal.errors[:pocket].any?
  end

  test "pocket must be of kind pocket" do
    account = MoneySource.create!(user: @user, name: "Davibank", kind: "account", starting_balance: 1_000_000)
    goal = Goal.new(user: @user, name: "Viaje", pocket: account, target_amount: 1_000_000)
    assert_not goal.valid?
    assert_includes goal.errors[:pocket], I18n.t("activerecord.errors.messages.not_a_pocket")
  end

  test "pocket must belong to the same user" do
    other_user = User.create!(name: "Other", email: "other_pocket@example.com", password: "password123")
    pocket = MoneySource.create!(user: other_user, name: "Otro bolsillo", kind: "pocket", starting_balance: 0)
    goal = Goal.new(user: @user, name: "Viaje", pocket: pocket, target_amount: 1_000_000)
    assert_not goal.valid?
    assert_includes goal.errors[:pocket], I18n.t("activerecord.errors.messages.other_user")
  end

  test "saved_amount is the sum of the goal's allocations" do
    goal = create_goal
    assert_equal 0, goal.saved_amount

    allocate(goal, 1_000_000)
    allocate(goal, 500_000)
    assert_equal 1_500_000, goal.saved_amount

    allocate(goal, -200_000)
    assert_equal 1_300_000, goal.saved_amount
  end

  test "goals inside the same pocket have independent saved amounts" do
    travel = create_goal(name: "Viaje Europa", target_amount: 20_000_000)
    car = create_goal(name: "Carro", target_amount: 30_000_000)

    allocate(travel, 2_000_000)
    allocate(car, 3_000_000)

    assert_equal 2_000_000, travel.reload.saved_amount
    assert_equal 3_000_000, car.reload.saved_amount
    assert_equal 15_000_000, @pocket.reload.unallocated_amount
  end

  test "saved_amount reads as zero for legacy goals without a pocket" do
    goal = create_goal
    goal.update_column(:pocket_id, nil)
    goal.reload
    assert_equal 0, goal.saved_amount
  end

  test "the pocket cannot be changed while the goal has allocations" do
    goal = create_goal
    allocate(goal, 1_000_000)
    other_pocket = create_pocket(starting_balance: 5_000_000)

    goal.pocket = other_pocket
    assert_not goal.save
    assert_includes goal.errors[:pocket], I18n.t("activerecord.errors.messages.pocket_locked_by_allocations")
  end

  test "target_date is optional" do
    assert create_goal(target_date: nil).valid?
    assert create_goal(target_date: Date.new(2026, 12, 31)).valid?
  end

  test "normalizes es-formatted target amount on save" do
    goal = Goal.new(user: @user, name: "Viaje", pocket: @pocket, target_amount: "5.000.000")
    assert goal.valid?
    assert_equal 5_000_000, goal.target_amount
  end

  test "progress_percentage caps at 100" do
    goal = create_goal
    allocate(goal, 9_999_999)
    assert_equal 100, goal.progress_percentage.round

    goal = create_goal
    allocate(goal, 2_000_000)
    assert_in_delta 40.0, goal.progress_percentage, 0.01
  end

  test "progress_percentage is zero for a zero target" do
    goal = Goal.new(user: @user, name: "Viaje", pocket: @pocket, target_amount: 0)
    assert_equal 0.0, goal.progress_percentage
  end

  test "remaining_amount returns the difference to the target" do
    goal = create_goal
    allocate(goal, 2_000_000)
    assert_in_delta 3_000_000, goal.remaining_amount, 0.01
  end

  test "completed? is true once the allocations reach the target" do
    goal = create_goal
    assert_not goal.completed?
    allocate(goal, 5_000_000)
    assert goal.reload.completed?
  end

  test "months_remaining counts whole months to the target date" do
    goal = create_goal(target_date: Date.current + 2.months)
    assert_equal 2, goal.months_remaining

    goal = create_goal(target_date: Date.current - 1.day)
    assert_equal 0, goal.months_remaining
  end

  test "months_remaining is nil without a target date" do
    assert_nil create_goal(target_date: nil).months_remaining
  end

  test "required_monthly_contribution divides remaining by months remaining" do
    goal = create_goal(target_date: Date.current + 2.months)
    allocate(goal, 2_000_000)
    # 3_000_000 remaining / 2 months
    assert_in_delta 1_500_000, goal.required_monthly_contribution, 0.01
  end

  test "required_monthly_contribution is nil without a target date" do
    assert_nil create_goal(target_date: nil).required_monthly_contribution
  end

  test "required_monthly_contribution is zero for a completed goal" do
    goal = create_goal(target_date: Date.current + 3.months)
    allocate(goal, 5_000_000)
    assert_equal 0, goal.reload.required_monthly_contribution
  end

  test "health is completed when the allocations reach the target" do
    goal = create_goal(target_date: Date.current + 3.months)
    allocate(goal, 5_000_000)
    assert_equal :completed, goal.reload.health
  end

  test "health is on_track without a target date" do
    assert_equal :on_track, create_goal(target_date: nil).health
  end

  test "health is behind when the target date passed" do
    goal = create_goal(target_date: Date.current - 1.day)
    assert_equal :behind, goal.health
  end

  test "health tracks the saving pace against the target date" do
    # Started 10 months ago, due in ~2 months (~12 total). Expected pace is
    # ~83% of the target.
    goal = create_goal(target_amount: 10_000_000, target_date: Date.current + 2.months)
    allocate(goal, 9_000_000)
    goal.update_column(:created_at, 10.months.ago)
    assert_equal :on_track, goal.health

    goal = create_goal(target_amount: 10_000_000, target_date: Date.current + 2.months)
    allocate(goal, 6_000_000)
    goal.update_column(:created_at, 10.months.ago)
    assert_equal :at_risk, goal.health

    goal = create_goal(target_amount: 10_000_000, target_date: Date.current + 2.months)
    allocate(goal, 2_000_000)
    goal.update_column(:created_at, 10.months.ago)
    assert_equal :behind, goal.health
  end

  test "status defaults to active and must be a known status" do
    assert_equal "active", create_goal.status
    assert create_goal(status: "archived").valid?

    goal = Goal.new(user: @user, name: "Viaje", pocket: @pocket, target_amount: 1_000_000, status: "nonsense")
    assert_not goal.valid?
  end

  test "priority must be a known value" do
    assert_equal Goal::PRIORITIES[:medium], create_goal.priority
    assert create_goal(priority: Goal::PRIORITIES[:high]).valid?

    goal = Goal.new(user: @user, name: "Viaje", pocket: @pocket, target_amount: 1_000_000, priority: 99)
    assert_not goal.valid?
  end

  test "category must be a known category when present" do
    assert create_goal(category: "travel").valid?

    goal = Goal.new(user: @user, name: "Viaje", pocket: @pocket, target_amount: 1_000_000, category: "nonsense")
    assert_not goal.valid?
  end
end
