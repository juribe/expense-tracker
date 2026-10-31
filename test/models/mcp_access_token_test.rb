# frozen_string_literal: true

require "test_helper"

class McpAccessTokenTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "MCP User", email: "mcp_token@example.com", password: "password123")
  end

  test "issues a readable token and stores only its digest" do
    token, plain = McpAccessToken.issue!(user: @user, name: "Claude", scopes: [ :read ])

    assert plain.present?
    assert_not_equal plain, token.token_digest
    assert_equal McpAccessToken.digest(plain), token.token_digest
    assert_equal [ "read" ], token.scopes
  end

  test "authenticates an active token" do
    _token, plain = McpAccessToken.issue!(user: @user, name: "Claude", scopes: [ :read, :write ])

    authenticated = McpAccessToken.authenticate(plain)

    assert_equal @user.id, authenticated.user_id
    assert authenticated.allows?(:write)
  end

  test "does not authenticate a revoked token" do
    token, plain = McpAccessToken.issue!(user: @user, name: "Claude", scopes: [ :read ])
    token.revoke!

    assert_nil McpAccessToken.authenticate(plain)
    assert token.reload.revoked?
  end

  test "does not authenticate an expired token" do
    token, plain = McpAccessToken.issue!(user: @user, name: "Claude", scopes: [ :read ])
    token.update!(expires_at: 1.minute.ago)

    assert_nil McpAccessToken.authenticate(plain)
    assert token.expired?
  end

  test "read scope does not allow write" do
    token, = McpAccessToken.issue!(user: @user, name: "Reader", scopes: [ :read ])

    assert token.allows?(:read)
    assert_not token.allows?(:write)
  end

  test "revoking records the timestamp" do
    token, = McpAccessToken.issue!(user: @user, name: "Claude", scopes: [ :read ])

    assert_nil token.revoked_at
    token.revoke!
    assert_not_nil token.reload.revoked_at
  end

  test "records the last usage" do
    token, = McpAccessToken.issue!(user: @user, name: "Claude", scopes: [ :read ])

    assert_nil token.last_used_at
    token.touch_last_used!
    assert_not_nil token.reload.last_used_at
  end
end
