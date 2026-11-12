# frozen_string_literal: true

require "test_helper"

# users/passwords: Devise password (recovery) flow with rate limiting on
# #create so password-reset requests can't be abused as an email flood.
class Users::PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: "Reset User", email: "users_passwords@example.com", password: "password123")
  end

  test "reset for a second-factor account stays pending until the second factor" do
    user = confirmed_user(email: "mfa_reset@example.com")
    user.create_totp_credential!(secret: TotpCredential.generate_secret)
    token = user.send_reset_password_instructions

    put user_password_path, params: {
      user: { reset_password_token: token, password: "newpassword123", password_confirmation: "newpassword123" }
    }

    assert_redirected_to new_user_two_factor_authentication_path
    assert_nil session["warden.user.user.key"]
    assert_equal user.id, session[:current_authentication_resource_id]
    assert user.reload.valid_password?("newpassword123")
  end

  test "reset without a second factor still signs in" do
    user = confirmed_user(email: "plain_reset@example.com")
    token = user.send_reset_password_instructions

    put user_password_path, params: {
      user: { reset_password_token: token, password: "newpassword123", password_confirmation: "newpassword123" }
    }

    assert session["warden.user.user.key"].present?
    assert_nil session[:current_authentication_resource_id]
  end

  test "POST rate limits the reset request after 5 posts in a minute" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    begin
      5.times do
        post user_password_path, params: { user: { email: @user.email } }
        assert_includes [ 200, 302, 303 ], response.status
      end

      post user_password_path, params: { user: { email: @user.email } }

      assert_equal 429, response.status
    ensure
      Rails.cache = original_cache
    end
  end

  private

  def confirmed_user(email:)
    User.create!(
      name: "Reset User",
      email: email,
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
  end
end
