# frozen_string_literal: true

require "test_helper"

class GoalsMoneyTrackingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "simple mode opens the goal form without pockets" do
    user = simple_user
    sign_in user

    get new_goal_path

    assert_response :success
    assert_select "#goal_pocket_id", count: 0
    assert_select "a[href*='kind=pocket']", count: 0
    assert_select "#goal_name"
    assert_select "#goal_target_amount"
  end

  test "simple mode creates a goal without a pocket" do
    user = simple_user
    sign_in user

    assert_difference "Goal.count", 1 do
      assert_no_difference "MoneySource.count" do
        post goals_path, params: { goal: { name: "Vacaciones", target_amount: "5.000.000" } }
      end
    end

    goal = Goal.order(:created_at).last
    assert_nil goal.pocket_id
    assert goal.virtual?
  end

  test "simple mode card hides pocket references and offers virtual actions" do
    user = simple_user
    goal = Goal.create!(user: user, name: "Vacaciones", target_amount: 5_000_000)
    goal.goal_allocations.create!(amount: 2_000_000, date: Date.current, note: "Primer aporte")
    sign_in user

    get goals_path

    assert_response :success
    assert_select "[data-testid=goal-card-pocket]", count: 0
    assert_select "a[href*='money_sources']", count: 0
    assert_select "[data-testid=goal-add-money]", text: /Agregar dinero/
    assert_select "[data-testid=goal-withdraw-money]", text: /Retirar dinero/
    assert_select "[data-testid=goal-history]", text: /Historial/
    assert_select "body", text: /Primer aporte/
    assert_select "[data-testid=goal-card-saved]", text: /\$2\.000\.000/
  end

  test "simple mode renders a pocket-backed goal without pocket references or virtual actions" do
    user = detailed_user
    pocket = user.money_sources.create!(name: "Ahorros", kind: "pocket", starting_balance: 2_000_000)
    goal = Goal.create!(user: user, pocket: pocket, name: "Viaje", target_amount: 5_000_000)
    goal.goal_allocations.create!(pocket: pocket, amount: 1_000_000, date: Date.current, note: "Reserva")
    user.update!(money_tracking_mode: "simple", money_tracking_mode_selected_at: Time.current)
    sign_in user

    get goals_path

    assert_response :success
    assert_select "[data-testid=goal-card-pocket]", count: 0
    assert_select "[data-testid=goal-add-money]", count: 0
    assert_select "[data-testid=goal-withdraw-money]", count: 0
    assert_select "[data-testid=goal-history]"
    assert_select "body", text: /avanzado/i
  end

  test "advanced mode keeps the pocket selector and rejects a goal without pocket" do
    user = detailed_user
    pocket = user.money_sources.create!(name: "Ahorros", kind: "pocket", starting_balance: 2_000_000)
    sign_in user

    get new_goal_path
    assert_response :success
    assert_select "select[name='goal[pocket_id]'] option", text: pocket.name

    assert_no_difference "Goal.count" do
      post goals_path, params: { goal: { name: "Vacaciones", target_amount: "5.000.000" } }
    end
    assert_response :unprocessable_entity
  end

  test "advanced mode keeps the pocket on the goal card" do
    user = detailed_user
    pocket = user.money_sources.create!(name: "Ahorros", kind: "pocket", starting_balance: 2_000_000)
    Goal.create!(user: user, pocket: pocket, name: "Viaje", target_amount: 5_000_000)
    sign_in user

    get goals_path

    assert_response :success
    assert_select "[data-testid=goal-card-pocket]", text: pocket.name
  end

  test "a virtual goal and its contributions survive switching to advanced" do
    user = simple_user
    goal = Goal.create!(user: user, name: "Vacaciones", target_amount: 5_000_000)
    goal.goal_allocations.create!(amount: 1_500_000, date: Date.current)
    user.update!(money_tracking_mode: "detailed", money_tracking_mode_selected_at: Time.current)
    sign_in user

    get goals_path

    assert_response :success
    assert_select "[data-testid=goal-card-name]", text: "Vacaciones"
    assert_select "[data-testid=goal-card-saved]", text: /\$1\.500\.000/
    assert_select "[data-testid=goal-virtual-badge]"
  end

  test "an advanced user can link a virtual goal to a funded pocket" do
    user = simple_user
    goal = Goal.create!(user: user, name: "Vacaciones", target_amount: 5_000_000)
    goal.goal_allocations.create!(amount: 1_000_000, date: Date.current)
    user.update!(money_tracking_mode: "detailed", money_tracking_mode_selected_at: Time.current)
    pocket = user.money_sources.create!(name: "Ahorros", kind: "pocket", starting_balance: 1_000_000)
    sign_in user

    patch link_to_pocket_goal_path(goal), params: { pocket_id: pocket.id }

    assert_redirected_to goals_path
    assert_equal pocket.id, goal.reload.pocket_id
    assert_equal 1_000_000, goal.saved_amount
    assert_equal pocket.id, goal.goal_allocations.first.pocket_id
  end

  test "an advanced user cannot link a virtual goal to an underfunded pocket" do
    user = simple_user
    goal = Goal.create!(user: user, name: "Vacaciones", target_amount: 5_000_000)
    goal.goal_allocations.create!(amount: 1_000_000, date: Date.current)
    user.update!(money_tracking_mode: "detailed", money_tracking_mode_selected_at: Time.current)
    pocket = user.money_sources.create!(name: "Ahorros", kind: "pocket", starting_balance: 500_000)
    sign_in user

    patch link_to_pocket_goal_path(goal), params: { pocket_id: pocket.id }

    assert_redirected_to goals_path
    assert goal.reload.virtual?
    assert_equal 500_000, pocket.reload.unallocated_amount
  end

  test "a satisfied virtual goal can be marked complete without losing history" do
    user = simple_user
    goal = Goal.create!(user: user, name: "Vacaciones", target_amount: 1_000_000)
    goal.goal_allocations.create!(amount: 1_000_000, date: Date.current, note: "Completado")
    sign_in user

    patch complete_goal_path(goal)

    assert_redirected_to goals_path
    goal.reload
    assert goal.archived?
    assert_equal 1_000_000, goal.saved_amount
    assert_equal 1, goal.goal_allocations.count
  end

  private

  def simple_user
    User.create!(name: "Goals Simple", email: "goals_simple_#{SecureRandom.hex(4)}@example.com",
                 password: "password123").tap do |user|
      user.update!(money_tracking_mode: "simple", money_tracking_mode_selected_at: Time.current)
    end
  end

  def detailed_user
    User.create!(name: "Goals Advanced", email: "goals_advanced_#{SecureRandom.hex(4)}@example.com",
                 password: "password123")
  end
end
