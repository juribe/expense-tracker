# frozen_string_literal: true

require "test_helper"

module Mcp
  class AuthenticationTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "MCP Auth", email: "mcp_auth@example.com", password: "password123")
      @token, @plain = McpAccessToken.issue!(user: @user, name: "Claude", scopes: [ :read, :write ])
    end

    test "resolves the user from a bearer token" do
      authenticated = Authentication.call(authorization: "Bearer #{@plain}")

      assert_equal @user.id, authenticated.user_id
      assert_equal [ "read", "write" ], authenticated.scopes
    end

    test "is case insensitive for the bearer scheme" do
      assert_equal @token.id, Authentication.call(authorization: "bearer #{@plain}").id
    end

    test "rejects a missing authorization header" do
      assert_raises(Authentication::Unauthenticated) do
        Authentication.call(authorization: nil)
      end
    end

    test "rejects an unknown token" do
      assert_raises(Authentication::Unauthenticated) do
        Authentication.call(authorization: "Bearer not-a-real-token")
      end
    end

    test "rejects a revoked token" do
      @token.revoke!

      assert_raises(Authentication::Unauthenticated) do
        Authentication.call(authorization: "Bearer #{@plain}")
      end
    end

    test "records when the token was last used" do
      Authentication.call(authorization: "Bearer #{@plain}")

      assert_not_nil @token.reload.last_used_at
    end
  end
end
