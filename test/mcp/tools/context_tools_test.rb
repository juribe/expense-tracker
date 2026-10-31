# frozen_string_literal: true

require "test_helper"
require_relative "../../support/mcp_tool_helper"

class ContextToolsTest < ActiveSupport::TestCase
  include McpToolHelper

  setup do
    @user = User.create!(name: "MCP Context", email: "mcp_context@example.com", password: "password123")
    @other_user = User.create!(name: "Other", email: "mcp_context_other@example.com", password: "password123")
    @category = Category.create!(name: "Transporte Contexto", is_default: true, category_type: "expense")
    @account = @user.money_sources.create!(name: "Cuenta Principal", kind: "account", starting_balance: 2_000_000)
    @pocket = @user.money_sources.create!(name: "Vacaciones", kind: "pocket", starting_balance: 500_000)
    @goal = Goal.create!(user: @user, pocket: @pocket, name: "Viaje", target_amount: 1_000_000)
    @budget = Budget.create!(user: @user, category: @category, monthly_amount: 300_000)
    @other_user.money_sources.create!(name: "Ajena", kind: "account", starting_balance: 9_999_999)
    @other_user.goals.create!(pocket: @other_user.money_sources.create!(name: "Bolsa Ajena", kind: "pocket"),
                              name: "Meta Ajena", target_amount: 100)
  end

  test "returns a compact profile with date, timezone and currency" do
    payload = invoke_tool(Mcp::Tools::Context::GetFinancialContextTool, user: @user)

    assert_equal true, payload["success"]
    profile = payload.dig("data", "profile")
    assert_equal Date.current.iso8601, profile["current_date"]
    assert_equal "America/Bogota", profile["timezone"]
    assert_equal "COP", profile["currency"]
  end

  test "includes the user's financial entities without transaction histories" do
    payload = invoke_tool(Mcp::Tools::Context::GetFinancialContextTool, user: @user)
    data = payload["data"]

    assert_equal @category.id, data["categories"].first["id"]
    assert_equal [ @account.id, @pocket.id ].sort, data["money_sources"].map { |source| source["id"] }.sort
    assert_equal [ @pocket.id ], data["pockets"].map { |pocket| pocket["id"] }
    assert_equal [ @goal.id ], data["savings_goals"].map { |goal| goal["id"] }
    assert_equal [ @budget.id ], data["budgets"].map { |budget| budget["id"] }

    assert_not data.key?("expenses")
    assert_not data.key?("incomes")
    assert_not data.key?("transfers")
  end

  test "does not leak another user's entities" do
    payload = invoke_tool(Mcp::Tools::Context::GetFinancialContextTool, user: @user)
    data = payload["data"]

    assert_not_includes data["money_sources"].map { |source| source["name"] }, "Ajena"
    assert_not_includes data["savings_goals"].map { |goal| goal["name"] }, "Meta Ajena"
  end

  test "limits the response to the requested sections" do
    payload = invoke_tool(Mcp::Tools::Context::GetFinancialContextTool, user: @user, sections: [ "budgets" ])
    data = payload["data"]

    assert data.key?("profile")
    assert data.key?("budgets")
    assert_not data.key?("money_sources")
    assert_not data.key?("pockets")
  end

  test "rejects unknown sections" do
    payload = invoke_tool(Mcp::Tools::Context::GetFinancialContextTool, user: @user, sections: [ "everything" ])

    assert_equal false, payload["success"]
    assert_equal "INVALID_ARGUMENT", payload.dig("error", "code")
  end

  test "accepts a comma separated section list" do
    payload = invoke_tool(Mcp::Tools::Context::GetFinancialContextTool, user: @user, sections: "budgets, pockets")

    assert_equal true, payload["success"]
    assert payload["data"].key?("budgets")
    assert payload["data"].key?("pockets")
    assert_not payload["data"].key?("money_sources")
  end

  test "lists money sources with decision attributes" do
    payload = invoke_tool(Mcp::Tools::Context::GetMoneySourcesTool, user: @user)
    sources = payload.dig("data", "money_sources")

    account = sources.find { |source| source["id"] == @account.id }
    assert_equal "account", account["kind"]
    assert_equal "2000000.0", account["balance"]
    assert_equal true, account["payment_source"]

    pocket = sources.find { |source| source["id"] == @pocket.id }
    assert_equal "pocket", pocket["kind"]
    assert_equal false, pocket["payment_source"]
  end

  test "filters money sources by kind" do
    payload = invoke_tool(Mcp::Tools::Context::GetMoneySourcesTool, user: @user, kind: "pocket")

    assert_equal [ @pocket.id ], payload.dig("data", "money_sources").map { |source| source["id"] }
  end

  test "does not load credit data when filtering to accounts" do
    queries = count_queries { invoke_tool(Mcp::Tools::Context::GetMoneySourcesTool, user: @user, kind: "account") }

    assert_equal 1, queries
  end

  test "preloads credit data in one query when debt sources are present" do
    @user.money_sources.create!(name: "Visa Contexto", kind: "credit_card", starting_balance: 0)

    queries = count_queries { invoke_tool(Mcp::Tools::Context::GetMoneySourcesTool, user: @user) }

    assert_equal 2, queries
  end
end
