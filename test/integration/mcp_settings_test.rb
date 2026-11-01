# frozen_string_literal: true

require "test_helper"

class McpSettingsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "MCP Settings", email: "mcp_settings@example.com", password: "password123")
    @other_user = User.create!(name: "Other", email: "mcp_settings_other@example.com", password: "password123")
  end

  test "shows the connections page with address and empty key state" do
    sign_in @user

    get mcp_settings_path

    assert_response :success
    assert_select "h1.page-title", text: /Conecta tu ChatGPT con Yogasto/
    assert_select "[data-testid='mcp-endpoint']", text: /#{Regexp.escape(mcp_endpoint_url)}/
    assert_select "#keyStatus", text: /Sin clave/
    assert_select "#copyPrompt[disabled]"
  end

  test "creates a key and shows it once" do
    sign_in @user

    post mcp_settings_path, params: { mcp_token: { name: "Mi asistente" } }

    assert_response :success
    plain = response.body[/ygm_[A-Za-z0-9_\-]+/]
    assert plain.present?
    assert_select "#keyValue", text: /#{Regexp.escape(plain)}/
    assert_select "#keyStatus", text: /Clave activa/
    assert_select "#reveal:not([disabled])"
    assert_select "#copyKey:not([disabled])"
    assert_select "#copyPrompt:not([disabled])"
    assert_select "#prompt", text: /#{Regexp.escape(plain)}/

    token = @user.mcp_access_tokens.order(:created_at).last
    assert_equal "Mi asistente", token.name
    assert_equal %w[read write], token.scopes

    get mcp_settings_path
    assert_no_match(/#{Regexp.escape(plain)}/, response.body)
    assert_select "#keyStatus", text: /Clave activa/
  end

  test "replaces the previous key when creating a new one" do
    sign_in @user
    old, = McpAccessToken.issue!(user: @user, name: "Antigua", scopes: %w[read write])

    post mcp_settings_path, params: { mcp_token: { name: "Nueva" } }

    assert_response :success
    assert old.reload.revoked?
    assert_equal 1, @user.mcp_access_tokens.active.count
  end

  test "does not revoke another user's key" do
    sign_in @user
    foreign, = McpAccessToken.issue!(user: @other_user, name: "Ajena", scopes: %w[read write])

    # Creating a key for @user must not touch @other_user's key.
    post mcp_settings_path, params: { mcp_token: { name: "Mia" } }

    assert_response :success
    assert_not foreign.reload.revoked?
  end

  test "requires authentication" do
    get mcp_settings_path

    assert_redirected_to new_user_session_path
  end
end
