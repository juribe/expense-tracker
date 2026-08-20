# frozen_string_literal: true

require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Test User",
      email: "sessions_test@example.com",
      password: "password123"
    )
  end

  test "DELETE /users/sign_out signs out a signed-in user" do
    sign_in @user
    delete destroy_user_session_path
    assert_response :redirect
    get dashboard_path
    assert_redirected_to new_user_session_path
  end

  test "GET /users/sign_out signs out a signed-in user without JavaScript" do
    sign_in @user
    get user_session_sign_out_get_path
    assert_response :redirect
    get dashboard_path
    assert_redirected_to new_user_session_path
  end

  test "GET /users/sign_out does not raise a routing error" do
    get "/users/sign_out"
    assert_response :redirect
  end
end
