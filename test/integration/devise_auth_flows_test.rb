# frozen_string_literal: true

require "test_helper"

class DeviseAuthFlowsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Test User",
      email: "auth_flow@example.com",
      password: "password123"
    )
  end

  test "sign up page renders the required fields and navigation links" do
    get new_user_registration_path
    assert_response :success
    assert_select "h1", text: "Create Account"
    assert_select "#user_name"
    assert_select "#user_email"
    assert_select "#user_password"
    assert_select "#user_password_confirmation"
    assert_select "button[type='submit']", text: "Create Account"
    assert_select "a[href='#{new_user_session_path}']", text: "Sign In"
  end

  test "sign up creates a user with name and signs them in" do
    assert_difference("User.count", 1) do
      post user_registration_path, params: {
        user: {
          name: "Jane Doe",
          email: "jane@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end
    user = User.find_by(email: "jane@example.com")
    assert_equal "Jane Doe", user.name
    assert_redirected_to root_path
    follow_redirect!
    assert_select ".sidebar-brand", /Expense Tracker/
  end

  test "sign up with mismatched passwords re-renders the form with errors" do
    assert_no_difference("User.count") do
      post user_registration_path, params: {
        user: {
          name: "Jane Doe",
          email: "jane@example.com",
          password: "password123",
          password_confirmation: "different123"
        }
      }
    end
    assert_response :unprocessable_entity
    assert_select "#error_explanation"
    assert_select ".alert-danger"
  end

  test "sign in page renders fields, remember me, forgot password and sign up link" do
    get new_user_session_path
    assert_response :success
    assert_select "h1", text: "Welcome back"
    assert_select "#user_email"
    assert_select "#user_password"
    assert_select "#user_remember_me"
    assert_select "a[href='#{new_user_password_path}']", text: "Forgot password?"
    assert_select "a[href='#{new_user_registration_path}']", text: "Sign up"
  end

  test "sign in with valid credentials redirects to the dashboard" do
    post user_session_path, params: {
      user: { email: @user.email, password: "password123" }
    }
    assert_redirected_to root_path
    follow_redirect!
    assert_equal @user.id, session["warden.user.user.key"].first.first
  end

  test "sign in with invalid credentials re-renders the form with an error" do
    post user_session_path, params: {
      user: { email: @user.email, password: "wrongpassword" }
    }
    assert_response :unprocessable_entity
    assert_select ".alert-danger"
  end

  test "forgot password page renders email field and back to sign in link" do
    get new_user_password_path
    assert_response :success
    assert_select "h1", text: "Forgot your password?"
    assert_select "#user_email"
    assert_select "button[type='submit']", text: "Send Reset Link"
    assert_select "a[href='#{new_user_session_path}']", text: "Back to Sign In"
  end

  test "forgot password sends a reset link and shows inline success" do
    assert_emails 1 do
      post user_password_path, params: { user: { email: @user.email } }
    end
    assert_response :success
    assert_select "h1", text: "Check your inbox"
    assert_select ".alert-success", /We've emailed a reset link/
    assert_equal @user.email, ActionMailer::Base.deliveries.last.to.first
  end

  test "forgot password with unknown email shows an error state" do
    assert_no_emails do
      post user_password_path, params: { user: { email: "nobody@example.com" } }
    end
    assert_response :unprocessable_entity
    assert_select "#error_explanation"
  end

  test "reset password page renders new password fields" do
    token = @user.send_reset_password_instructions
    get edit_user_password_path(reset_password_token: token)
    assert_response :success
    assert_select "h1", text: "Reset your password"
    assert_select "#user_password"
    assert_select "#user_password_confirmation"
    assert_select "button[type='submit']", text: "Reset Password"
  end

  test "reset password updates the password and shows inline success" do
    token = @user.send_reset_password_instructions
    patch user_password_path, params: {
      user: {
        reset_password_token: token,
        password: "newpassword456",
        password_confirmation: "newpassword456"
      }
    }
    assert_response :success
    assert_select "h1", text: "Password updated"
    assert_select ".alert-success", /Your password has been updated/
    assert_select "[data-auto-redirect-to='#{root_path}']"
    assert @user.reload.valid_password?("newpassword456")
    assert_equal @user.id, session["warden.user.user.key"].first.first
  end

  test "reset password with mismatched confirmation shows errors" do
    token = @user.send_reset_password_instructions
    patch user_password_path, params: {
      user: {
        reset_password_token: token,
        password: "newpassword456",
        password_confirmation: "different456"
      }
    }
    assert_response :unprocessable_entity
    assert_select "#error_explanation"
    assert_not @user.reload.valid_password?("newpassword456")
  end
end
