# frozen_string_literal: true

require "test_helper"

# users/sessions: Devise sign-in flow with rate limiting on #create so a
# script can't brute force credentials (100/min outside production).
class Users::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: "Login User", email: "users_sessions_test@example.com", password: "password123")
  end

  test "POST rate limits the sign-in attempt after 100 posts in a minute" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    begin
      100.times do
        post user_session_path, params: { user: { email: @user.email, password: "wrong-password" } }
        assert_includes [ 200, 302, 422 ], response.status
      end

      post user_session_path, params: { user: { email: @user.email, password: "wrong-password" } }

      assert_equal 429, response.status
    ensure
      Rails.cache = original_cache
    end
  end

  test "a corrected sign-in attempt keeps working" do
    post user_session_path, params: { user: { email: @user.email, password: "password123" } }

    assert_redirected_to root_path
  end
end
