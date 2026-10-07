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
    sign_in @user
  end

  test "GET /goals renders the index with the user's goals" do
    goal = Goal.create!(user: @user, name: "Fondo de emergencia", target_amount: 5_000_000, saved_amount: 2_000_000)
    get goals_path
    assert_response :success
    assert_select "h1", text: /Metas/
    assert_select "a[href=?]", new_goal_path
    assert_select "a[href=?]", edit_goal_path(goal)
  end

  test "GET /goals shows an empty state without goals" do
    get goals_path
    assert_response :success
    assert_select "a[href=?]", new_goal_path
  end

  test "GET /goals/new renders the form" do
    get new_goal_path
    assert_response :success
    assert_select "form[action=?]", goals_path
  end

  test "POST /goals creates a goal for the current user" do
    assert_difference("Goal.count", 1) do
      post goals_path, params: { goal: { name: "Viaje familiar", target_amount: "3.000.000", saved_amount: "1.200.000" } }
    end
    goal = Goal.last
    assert_equal @user, goal.user
    assert_equal "Viaje familiar", goal.name
    assert_equal 3_000_000, goal.target_amount
    assert_equal 1_200_000, goal.saved_amount
    assert_redirected_to goals_path
  end

  test "POST /goals with invalid data re-renders the form" do
    assert_no_difference("Goal.count") do
      post goals_path, params: { goal: { name: "", target_amount: "0" } }
    end
    assert_response :unprocessable_entity
  end

  test "GET /goals/1/edit renders the form" do
    goal = Goal.create!(user: @user, name: "Viaje", target_amount: 1_000_000)
    get edit_goal_path(goal)
    assert_response :success
    assert_select "form[action=?]", goal_path(goal)
  end

  test "PATCH /goals/1 updates the goal" do
    goal = Goal.create!(user: @user, name: "Viaje", target_amount: 1_000_000)
    patch goal_path(goal), params: { goal: { name: "Viaje familiar", saved_amount: "500.000" } }
    goal.reload
    assert_equal "Viaje familiar", goal.name
    assert_equal 500_000, goal.saved_amount
    assert_redirected_to goals_path
  end

  test "DELETE /goals/1 destroys the goal" do
    goal = Goal.create!(user: @user, name: "Viaje", target_amount: 1_000_000)
    assert_difference("Goal.count", -1) do
      delete goal_path(goal)
    end
    assert_redirected_to goals_path
  end

  test "other users' goals are not reachable" do
    other_user = User.create!(name: "Other", email: "other_goals@example.com", password: "password123")
    goal = Goal.create!(user: other_user, name: "Viaje", target_amount: 1_000_000)

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
