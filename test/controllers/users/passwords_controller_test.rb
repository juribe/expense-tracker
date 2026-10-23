# frozen_string_literal: true

require "test_helper"

# users/passwords: Devise password (recovery) flow with rate limiting on
# #create so password-reset requests can't be abused as an email flood.
class Users::PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: "Reset User", email: "users_passwords@example.com", password: "password123")
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
end
