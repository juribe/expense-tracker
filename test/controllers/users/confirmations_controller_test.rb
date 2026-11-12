# frozen_string_literal: true

require "test_helper"

# users/confirmations: resending a confirmation email is rate limited per IP.
class Users::ConfirmationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      name: "Confirm User",
      email: "confirm-rate@example.com",
      password: "password123"
    )
  end

  test "POST rate limits confirmation requests after 5 posts in a minute" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    begin
      5.times do
        post user_confirmation_path, params: { user: { email: @user.email } }
        assert_includes [ 200, 302, 303 ], response.status
      end

      post user_confirmation_path, params: { user: { email: @user.email } }

      assert_equal 429, response.status
    ensure
      Rails.cache = original_cache
    end
  end
end
