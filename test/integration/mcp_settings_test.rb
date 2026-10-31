# frozen_string_literal: true

require "test_helper"

class McpSettingsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "MCP Settings", email: "mcp_settings@example.com", password: "password123")
    @other_user = User.create!(name: "Other", email: "mcp_settings_other@example.com", password: "password123")
  end

  test "shows the token management page" do
    sign_in @user

    get mcp_settings_path

    assert_response :success
    assert_select "h5", text: /MCP/
    assert_select "form[action=?]", mcp_settings_path
  end

  test "creates a token with write access and shows it once" do
    sign_in @user

    post mcp_settings_path, params: { mcp_token: { name: "Claude", write_access: "1" } }

    assert_response :success
    plain = response.body[/ygm_[A-Za-z0-9_\-]+/]
    assert plain.present?

    token = @user.mcp_access_tokens.order(:created_at).last
    assert_equal "Claude", token.name
    assert_equal %w[read write], token.scopes
    assert_equal McpAccessToken.digest(plain), token.token_digest

    get mcp_settings_path
    assert_no_match(/#{Regexp.escape(plain)}/, response.body)
  end

  test "creates a read-only token when write access is unchecked" do
    sign_in @user

    post mcp_settings_path, params: { mcp_token: { name: "Reader" } }

    assert_response :success
    assert_equal [ "read" ], @user.mcp_access_tokens.order(:created_at).last.scopes
  end

  test "revokes one of the user's tokens" do
    sign_in @user
    token, = McpAccessToken.issue!(user: @user, name: "Claude", scopes: [ :read ])

    delete mcp_settings_token_path(token)

    assert_redirected_to mcp_settings_path
    assert token.reload.revoked?
  end

  test "does not revoke another user's token" do
    sign_in @user
    foreign, = McpAccessToken.issue!(user: @other_user, name: "Ajena", scopes: [ :read ])

    delete mcp_settings_token_path(foreign)

    assert_response :not_found
    assert_not foreign.reload.revoked?
  end

  test "requires authentication" do
    get mcp_settings_path

    assert_redirected_to new_user_session_path
  end
end
