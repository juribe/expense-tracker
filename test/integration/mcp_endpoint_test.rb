# frozen_string_literal: true

require "test_helper"

class McpEndpointTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: "MCP Endpoint", email: "mcp_endpoint@example.com", password: "password123")
    @token, @plain = McpAccessToken.issue!(user: @user, name: "Test client", scopes: [ :read, :write ])
    @category = Category.create!(name: "Transporte MCP", is_default: true, category_type: "expense")

    other_user = User.create!(name: "Other", email: "mcp_other@example.com", password: "password123")
    @foreign_category = Category.create!(name: "Ajena MCP", user: other_user, category_type: "expense")
  end

  test "initialize completes the JSON-RPC handshake" do
    post_mcp(jsonrpc: "2.0", id: 1, method: "initialize",
             params: { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "test", version: "1" } })

    assert_response :success
    body = json_body
    assert_equal "2.0", body["jsonrpc"]
    assert_equal "yogasto", body.dig("result", "serverInfo", "name")
    assert_equal "2024-11-05", body.dig("result", "protocolVersion")
  end

  test "tools/list exposes the context tool" do
    post_mcp(jsonrpc: "2.0", id: 2, method: "tools/list")

    assert_response :success
    names = json_body.dig("result", "tools").map { |tool| tool["name"] }
    assert_includes names, "get_categories"
  end

  test "tools/call returns structured JSON for a successful query" do
    call_tool("get_categories", {})

    assert_response :success
    payload = tool_payload
    assert_equal true, payload["success"]
    names = payload.dig("data", "categories").map { |category| category["name"] }
    assert_includes names, @category.name
    assert_not_includes names, @foreign_category.name
  end

  test "tools/call rejects invalid arguments with a stable code" do
    call_tool("get_categories", { category_type: "transfer" })

    assert_response :success
    result = json_body["result"]
    assert_equal true, result["isError"]
    payload = tool_payload
    assert_equal false, payload["success"]
    assert_equal "INVALID_ARGUMENT", payload.dig("error", "code")
  end

  test "rejects requests without a token" do
    post_mcp({ jsonrpc: "2.0", id: 3, method: "tools/list" }, token: nil)

    assert_response :unauthorized
    assert_equal(-32_001, json_body.dig("error", "code"))
  end

  test "rejects a revoked token" do
    @token.revoke!

    post_mcp(jsonrpc: "2.0", id: 4, method: "tools/list")

    assert_response :unauthorized
  end

  test "handles consecutive calls without any session state" do
    2.times do
      call_tool("get_categories", {})
      assert_response :success
      assert_equal true, tool_payload["success"]
    end
  end

  test "answers 202 for notifications without a response body" do
    post_mcp(jsonrpc: "2.0", method: "notifications/initialized")

    assert_response :accepted
  end

  test "does not serve other HTTP methods" do
    get "/mcp", headers: { "AUTHORIZATION" => "Bearer #{@plain}" }

    assert_response :method_not_allowed
    assert_equal(-32_601, json_body.dig("error", "code"))
  end

  test "read-only tokens only see read tools" do
    _token, plain = McpAccessToken.issue!(user: @user, name: "Reader", scopes: [ :read ])

    post_mcp({ jsonrpc: "2.0", id: 20, method: "tools/list" }, token: plain)
    names = json_body.dig("result", "tools").map { |tool| tool["name"] }

    assert_includes names, "get_expenses"
    assert_not_includes names, "create_expense"
  end

  test "read-only tokens cannot call a write tool" do
    _token, plain = McpAccessToken.issue!(user: @user, name: "Reader", scopes: [ :read ])

    post_mcp({ jsonrpc: "2.0", id: 21, method: "tools/call",
               params: { name: "create_expense", arguments: {} } }, token: plain)

    assert_equal(-32_602, json_body.dig("error", "code"))
    assert_match(/Tool not found/, json_body.dig("error", "message"))
  end

  test "write tokens see write tools" do
    post_mcp(jsonrpc: "2.0", id: 22, method: "tools/list")
    names = json_body.dig("result", "tools").map { |tool| tool["name"] }

    assert_includes names, "create_expense"
    assert_includes names, "create_transfer"
  end

  test "rejects every MCP method when the user has no premium access" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)

    [
      { jsonrpc: "2.0", id: 30, method: "initialize",
        params: { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "test", version: "1" } } },
      { jsonrpc: "2.0", id: 31, method: "tools/list" },
      { jsonrpc: "2.0", id: 32, method: "tools/call",
        params: { name: "get_categories", arguments: {} } },
      { jsonrpc: "2.0", method: "notifications/initialized" }
    ].each do |payload|
      post_mcp(payload)

      assert_response :forbidden
      assert_equal(-32_003, json_body.dig("error", "code"))
      assert_match(/premium membership/i, json_body.dig("error", "message"))
    end
  end

  test "rejects requests when the premium membership is expired" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    create_membership(status: "active", expires_at: 1.day.ago)

    post_mcp(jsonrpc: "2.0", id: 33, method: "tools/list")

    assert_response :forbidden
    assert_equal(-32_003, json_body.dig("error", "code"))
  end

  test "allows requests when the user has an active premium membership" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    create_membership(status: "active", expires_at: 1.month.from_now)

    post_mcp(jsonrpc: "2.0", id: 34, method: "tools/list")

    assert_response :success
    names = json_body.dig("result", "tools").map { |tool| tool["name"] }
    assert_includes names, "get_categories"
  end

  test "allows requests without membership when paid access is not required" do
    PaymentEngine::Setting.current.update!(paid_access_required: false)

    post_mcp(jsonrpc: "2.0", id: 35, method: "tools/list")

    assert_response :success
  end

  test "renewing the membership restores access for the same token" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    membership = create_membership(status: "expired", expires_at: 1.day.ago)

    post_mcp(jsonrpc: "2.0", id: 36, method: "tools/list")
    assert_response :forbidden

    membership.update!(status: "active", expires_at: 1.month.from_now)

    post_mcp(jsonrpc: "2.0", id: 37, method: "tools/list")
    assert_response :success
  end

  test "an expired user does not affect another user's access" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    create_membership(status: "expired", expires_at: 1.day.ago)

    other_user = User.create!(name: "MCP Premium", email: "mcp_premium@example.com", password: "password123")
    create_membership(user: other_user, status: "active", expires_at: 1.month.from_now)
    _other_token, other_plain = McpAccessToken.issue!(user: other_user, name: "Premium client", scopes: [ :read ])

    post_mcp(jsonrpc: "2.0", id: 40, method: "tools/list")
    assert_response :forbidden

    post_mcp({ jsonrpc: "2.0", id: 41, method: "tools/list" }, token: other_plain)
    assert_response :success
  end

  private

  def create_membership(status:, expires_at:, user: @user)
    PaymentEngine::Membership.create!(
      owner: user,
      membership_type: membership_type,
      status: status,
      source: "purchase",
      starts_at: 1.month.ago,
      expires_at: expires_at
    )
  end

  def membership_type
    @membership_type ||= PaymentEngine::MembershipType.create!(
      name: "MCP Endpoint Premium",
      code: "MCP_ENDPOINT_#{SecureRandom.hex(6)}",
      status: "active"
    )
  end

  def post_mcp(payload = nil, token: @plain, **payload_keywords)
    payload ||= payload_keywords
    headers = { "CONTENT_TYPE" => "application/json" }
    headers["AUTHORIZATION"] = "Bearer #{token}" if token
    post "/mcp", params: JSON.generate(payload), headers: headers
  end

  def call_tool(name, arguments)
    post_mcp(jsonrpc: "2.0", id: 10, method: "tools/call", params: { name: name, arguments: arguments })
  end

  def json_body
    JSON.parse(response.body)
  end

  def tool_payload
    JSON.parse(json_body.dig("result", "content", 0, "text"))
  end
end
