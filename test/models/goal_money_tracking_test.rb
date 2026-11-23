# frozen_string_literal: true

require "test_helper"

class GoalMoneyTrackingTest < ActiveSupport::TestCase
  test "simple mode creates a goal without a pocket" do
    user = simple_user

    goal = Goal.create!(user: user, name: "Vacaciones", target_amount: 5_000_000)

    assert goal.persisted?
    assert goal.virtual?
    assert_nil goal.pocket_id
    assert_equal 0, user.money_sources.where(kind: "pocket").count
  end

  test "advanced mode still requires a pocket for a new goal" do
    user = detailed_user

    goal = Goal.new(user: user, name: "Vacaciones", target_amount: 5_000_000)

    refute goal.valid?
    assert goal.errors[:pocket].any?
  end

  test "an existing virtual goal survives an advanced-mode edit" do
    user = simple_user
    goal = Goal.create!(user: user, name: "Vacaciones", target_amount: 5_000_000)
    user.update!(money_tracking_mode: "detailed", money_tracking_mode_selected_at: Time.current)

    goal.update!(name: "Vacaciones 2027")

    assert_equal "Vacaciones 2027", goal.reload.name
    assert goal.virtual?
  end

  test "a virtual goal's saved amount comes only from virtual allocations" do
    user = simple_user
    goal = Goal.create!(user: user, name: "Vacaciones", target_amount: 5_000_000)

    goal.goal_allocations.create!(amount: 2_000_000, date: Date.current, note: "Aporte")
    goal.goal_allocations.create!(amount: -500_000, date: Date.current, note: "Retiro")

    assert_equal 1_500_000, goal.reload.saved_amount
    assert_in_delta 30.0, goal.progress_percentage, 0.01
  end

  test "a pocket-backed goal ignores virtual allocations that are not counted" do
    user = detailed_user
    pocket = user.money_sources.create!(name: "Ahorros", kind: "pocket", starting_balance: 5_000_000)
    goal = Goal.create!(user: user, pocket: pocket, name: "Vacaciones", target_amount: 5_000_000)
    goal.goal_allocations.create!(pocket: pocket, amount: 1_000_000, date: Date.current)
    # Defensive data: a virtual row must not inflate a pocket-backed goal.
    goal.goal_allocations.create!(pocket: nil, amount: 4_000_000, date: Date.current).update_column(:pocket_id, nil)

    assert_equal 1_000_000, goal.reload.saved_amount
  end

  private

  def simple_user
    User.create!(name: "Goal Simple", email: "goal_simple_#{SecureRandom.hex(4)}@example.com",
                 password: "password123").tap do |user|
      user.update!(money_tracking_mode: "simple", money_tracking_mode_selected_at: Time.current)
    end
  end

  def detailed_user
    User.create!(name: "Goal Advanced", email: "goal_advanced_#{SecureRandom.hex(4)}@example.com",
                 password: "password123")
  end
end
