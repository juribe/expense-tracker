# frozen_string_literal: true

require "test_helper"

class GoalsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Test User",
      email: "goals_controller_test@example.com",
      password: "password123"
    )
    @pocket = MoneySource.create!(user: @user, name: "Bolsillo Viaje", kind: "pocket", starting_balance: 2_000_000)
    sign_in @user
  end

  test "GET /goals renders the index with the user's goals" do
    goal = Goal.create!(user: @user, pocket: @pocket, name: "Fondo de emergencia", target_amount: 5_000_000)
    get goals_path
    assert_response :success
    assert_select "h1", text: /Metas/
    assert_select "a[href=?]", new_goal_path
    assert_select "a[href=?]", edit_goal_path(goal)
    assert_select "a[href=?]", money_source_path(@pocket)
  end

  test "GET /goals shows an empty state without goals" do
    get goals_path
    assert_response :success
    assert_select "a[href=?]", new_goal_path
  end

  test "GET /goals/new renders the form with the pocket options" do
    get new_goal_path
    assert_response :success
    assert_select "form[action=?]", goals_path
    assert_select "select[name=?] option", "goal[pocket_id]", text: @pocket.name
  end

  test "GET /goals/new offers to create a pocket when the user has none" do
    @pocket.destroy!
    get new_goal_path
    assert_response :success
    assert_select "a[href=?]", new_money_source_path(kind: "pocket")
  end

  test "POST /goals creates a goal backed by the chosen pocket" do
    assert_difference("Goal.count", 1) do
      post goals_path, params: { goal: {
        name: "Viaje familiar", target_amount: "3.000.000", pocket_id: @pocket.id,
        priority: Goal::PRIORITIES[:high].to_s, category: "travel"
      } }
    end
    goal = Goal.last
    assert_equal @user, goal.user
    assert_equal "Viaje familiar", goal.name
    assert_equal 3_000_000, goal.target_amount
    assert_equal @pocket, goal.pocket
    assert_equal Goal::PRIORITIES[:high], goal.priority
    assert_equal "travel", goal.category
    # Saved starts at zero: it only grows with goal allocations, not with the
    # pocket's balance.
    assert_equal 0, goal.saved_amount.to_i
    assert_redirected_to goals_path
  end

  test "POST /goals ignores a manually provided saved amount" do
    post goals_path, params: { goal: { name: "Viaje", target_amount: "1.000.000", saved_amount: "999.999", pocket_id: @pocket.id } }
    goal = Goal.last
    assert_equal 0, goal.saved_amount.to_i
  end

  test "POST /goals without a pocket re-renders the form" do
    assert_no_difference("Goal.count") do
      post goals_path, params: { goal: { name: "Viaje", target_amount: "1.000.000" } }
    end
    assert_response :unprocessable_entity
  end

  test "POST /goals rejects a pocket from another user" do
    other_user = User.create!(name: "Other", email: "other_goals_pocket@example.com", password: "password123")
    other_pocket = MoneySource.create!(user: other_user, name: "Ajeno", kind: "pocket", starting_balance: 0)

    assert_no_difference("Goal.count") do
      post goals_path, params: { goal: { name: "Viaje", target_amount: "1.000.000", pocket_id: other_pocket.id } }
    end
    assert_response :unprocessable_entity
  end

  test "POST /goals with invalid data re-renders the form" do
    assert_no_difference("Goal.count") do
      post goals_path, params: { goal: { name: "", target_amount: "0", pocket_id: @pocket.id } }
    end
    assert_response :unprocessable_entity
  end

  test "GET /goals/1/edit renders the form" do
    goal = Goal.create!(user: @user, pocket: @pocket, name: "Viaje", target_amount: 1_000_000)
    get edit_goal_path(goal)
    assert_response :success
    assert_select "form[action=?]", goal_path(goal)
  end

  test "PATCH /goals/1 updates the goal" do
    goal = Goal.create!(user: @user, pocket: @pocket, name: "Viaje", target_amount: 1_000_000)
    patch goal_path(goal), params: { goal: { name: "Viaje familiar", priority: Goal::PRIORITIES[:low].to_s, status: "archived" } }
    goal.reload
    assert_equal "Viaje familiar", goal.name
    assert_equal Goal::PRIORITIES[:low], goal.priority
    assert_equal "archived", goal.status
    # saved_amount is never editable: it only comes from allocations.
    assert_equal 0, goal.saved_amount.to_i
    assert_redirected_to goals_path
  end

  test "DELETE /goals/1 destroys the goal and keeps the pocket" do
    goal = Goal.create!(user: @user, pocket: @pocket, name: "Viaje", target_amount: 1_000_000)
    assert_no_difference("MoneySource.count") do
      assert_difference("Goal.count", -1) do
        delete goal_path(goal)
      end
    end
    assert_redirected_to goals_path
  end

  test "other users' goals are not reachable" do
    other_user = User.create!(name: "Other", email: "other_goals@example.com", password: "password123")
    other_pocket = MoneySource.create!(user: other_user, name: "Ajeno", kind: "pocket", starting_balance: 0)
    goal = Goal.create!(user: other_user, pocket: other_pocket, name: "Viaje", target_amount: 1_000_000)

    get edit_goal_path(goal)
    assert_redirected_to goals_path

    patch goal_path(goal), params: { goal: { name: "Hacked" } }
    assert_redirected_to goals_path
    assert_equal "Viaje", goal.reload.name

    assert_no_difference("Goal.count") do
      delete goal_path(goal)
    end
  end
end
