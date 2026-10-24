# frozen_string_literal: true

require "test_helper"

class Users::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Old Name",
      email: "registrations_ctrl_test@example.com",
      password: "password123"
    )
    @user.confirm
    sign_in @user
  end

  test "PUT /users stays signed in with a changed name without passwords" do
    put user_registration_path, params: {
      user: {
        name: "Nuevo Nombre",
        email: @user.email,
        password: "",
        password_confirmation: "",
        current_password: ""
      }
    }

    assert_redirected_to root_path
    @user.reload
    assert_equal "Nuevo Nombre", @user.name
  end

  test "email change without the current password is rejected" do
    put user_registration_path, params: {
      user: {
        name: @user.name,
        email: "new-email@example.com",
        password: "",
        password_confirmation: "",
        current_password: ""
      }
    }

    assert_response :unprocessable_entity
    @user.reload
    assert_equal "registrations_ctrl_test@example.com", @user.email
  end

  test "email change with the current password is queued for confirmation" do
    put user_registration_path, params: {
      user: {
        name: @user.name,
        email: "new-email@example.com",
        password: "",
        password_confirmation: "",
        current_password: "password123"
      }
    }

    assert_redirected_to root_path
    @user.reload
    assert_equal "registrations_ctrl_test@example.com", @user.email
    assert_equal "new-email@example.com", @user.unconfirmed_email
  end
end
