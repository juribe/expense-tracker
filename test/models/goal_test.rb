# frozen_string_literal: true

require "test_helper"

class GoalTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Test User", email: "goal_test@example.com", password: "password123")
  end

  def create_goal(**overrides)
    Goal.create!({ user: @user, name: "Fondo de emergencia", target_amount: 5_000_000, saved_amount: 2_000_000 }.merge(overrides))
  end

  test "is valid with required attributes" do
    goal = Goal.new(user: @user, name: "Viaje", target_amount: 1_000_000)
    assert goal.valid?
  end

  test "name is required" do
    goal = Goal.new(user: @user, target_amount: 1_000_000)
    assert_not goal.valid?
    assert_includes goal.errors[:name], I18n.t("errors.messages.blank")
  end

  test "user is required" do
    goal = Goal.new(name: "Viaje", target_amount: 1_000_000)
    assert_not goal.valid?
    assert goal.errors[:user].any?
  end

  test "target_amount is required and must be positive" do
    goal = Goal.new(user: @user, name: "Viaje")
    assert_not goal.valid?
    assert_includes goal.errors[:target_amount], I18n.t("errors.messages.blank")

    goal.target_amount = 0
    assert_not goal.valid?
    assert_includes goal.errors[:target_amount], I18n.t("errors.messages.greater_than", count: 0)
  end

  test "saved_amount cannot be negative" do
    goal = Goal.new(user: @user, name: "Viaje", target_amount: 1_000_000, saved_amount: -1)
    assert_not goal.valid?
    assert_includes goal.errors[:saved_amount], I18n.t("errors.messages.greater_than_or_equal_to", count: 0)
  end

  test "saved_amount defaults to zero" do
    goal = Goal.new(user: @user, name: "Viaje", target_amount: 1_000_000)
    assert_equal 0, goal.saved_amount
  end

  test "target_date is optional" do
    assert create_goal(target_date: nil).valid?
    assert create_goal(target_date: Date.new(2026, 12, 31)).valid?
  end

  test "normalizes es-formatted amounts on save" do
    goal = Goal.new(user: @user, name: "Viaje", target_amount: "5.000.000", saved_amount: "2.000.000,50")
    assert goal.valid?
    assert_equal 5_000_000, goal.target_amount
    assert_equal 2_000_000.5, goal.saved_amount
  end

  test "progress_percentage caps at 100" do
    goal = create_goal(saved_amount: 9_999_999)
    assert_equal 100, goal.progress_percentage.round

    goal = create_goal(saved_amount: 2_000_000)
    assert_in_delta 40.0, goal.progress_percentage, 0.01
  end

  test "progress_percentage is zero for a zero target" do
    goal = Goal.new(user: @user, name: "Viaje", target_amount: 0)
    assert_equal 0.0, goal.progress_percentage
  end

  test "remaining_amount returns the difference to the target" do
    goal = create_goal
    assert_in_delta 3_000_000, goal.remaining_amount, 0.01
  end

  test "completed? is true once the target is reached" do
    assert_not create_goal.completed?
    assert create_goal(saved_amount: 5_000_000).completed?
  end
end
