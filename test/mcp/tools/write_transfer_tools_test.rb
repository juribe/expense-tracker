# frozen_string_literal: true

require "test_helper"
require_relative "../../support/mcp_tool_helper"

class WriteTransferToolsTest < ActiveSupport::TestCase
  include McpToolHelper

  setup do
    @user = User.create!(name: "MCP Transfers", email: "mcp_transfers@example.com", password: "password123")
    @other_user = User.create!(name: "Other", email: "mcp_transfers_other@example.com", password: "password123")
    @account = @user.money_sources.create!(name: "Ahorros", kind: "account", starting_balance: 1_000_000)
    @cash = @user.money_sources.create!(name: "Efectivo", kind: "cash", starting_balance: 0)
    @pocket = @user.money_sources.create!(name: "Viaje", kind: "pocket", starting_balance: 0)
    @foreign = @other_user.money_sources.create!(name: "Ajena", kind: "account", starting_balance: 1_000_000)
  end

  test "transfers money between two sources" do
    payload = invoke_tool(Mcp::Tools::Transfers::CreateTransferTool, user: @user,
                          amount: "200000", date: Date.current.iso8601,
                          source_id: @account.id, destination_id: @cash.id,
                          description: "Retiro")

    assert_equal true, payload["success"]
    assert_equal BigDecimal("800000"), @account.reload.balance
    assert_equal BigDecimal("200000"), @cash.reload.balance
    assert_equal "Retiro", payload.dig("data", "description")
  end

  test "rejects a transfer above the available balance" do
    assert_no_difference "Transfer.count" do
      payload = invoke_tool(Mcp::Tools::Transfers::CreateTransferTool, user: @user,
                            amount: "2000000", date: Date.current.iso8601,
                            source_id: @account.id, destination_id: @cash.id)

      assert_equal false, payload["success"]
      assert_equal "INSUFFICIENT_FUNDS", payload.dig("error", "code")
    end
  end

  test "rejects another user's source" do
    payload = invoke_tool(Mcp::Tools::Transfers::CreateTransferTool, user: @user,
                          amount: "1000", date: Date.current.iso8601,
                          source_id: @foreign.id, destination_id: @cash.id)

    assert_equal false, payload["success"]
    assert_equal "INVALID_MONEY_SOURCE", payload.dig("error", "code")
  end

  test "allocates money to a pocket and withdraws it back" do
    payload = invoke_tool(Mcp::Tools::Pockets::AllocateToPocketTool, user: @user,
                          pocket_id: @pocket.id, amount: "100000",
                          source_id: @account.id, date: Date.current.iso8601)
    assert_equal true, payload["success"]
    assert_equal BigDecimal("100000"), @pocket.reload.balance

    payload = invoke_tool(Mcp::Tools::Pockets::WithdrawFromPocketTool, user: @user,
                          pocket_id: @pocket.id, amount: "40000",
                          destination_id: @account.id, date: Date.current.iso8601)
    assert_equal true, payload["success"]
    assert_equal BigDecimal("60000"), @pocket.reload.balance
    assert_equal BigDecimal("940000"), @account.reload.balance
  end

  test "refuses a pocket withdrawal that would break goal reservations" do
    goal = Goal.create!(user: @user, pocket: @pocket, name: "Meta", target_amount: 500_000)
    invoke_tool(Mcp::Tools::Pockets::AllocateToPocketTool, user: @user,
                pocket_id: @pocket.id, amount: "100000",
                source_id: @account.id, date: Date.current.iso8601)
    GoalAllocation.create!(financial_goal: goal, amount: 80_000, date: Date.current)

    payload = invoke_tool(Mcp::Tools::Pockets::WithdrawFromPocketTool, user: @user,
                          pocket_id: @pocket.id, amount: "50000",
                          destination_id: @account.id, date: Date.current.iso8601)

    assert_equal false, payload["success"]
    assert_equal "INVALID_ARGUMENT", payload.dig("error", "code")
    assert_equal BigDecimal("100000"), @pocket.reload.balance
  end

  test "is idempotent when allocating to a pocket" do
    key = SecureRandom.uuid
    arguments = { pocket_id: @pocket.id, amount: "100000", source_id: @account.id,
                  date: Date.current.iso8601, idempotency_key: key }

    first = invoke_tool(Mcp::Tools::Pockets::AllocateToPocketTool, user: @user, **arguments)
    assert_equal true, first["success"]

    assert_no_difference "Transfer.count" do
      second = invoke_tool(Mcp::Tools::Pockets::AllocateToPocketTool, user: @user, **arguments)
      assert_equal first.dig("data", "id"), second.dig("data", "id")
    end
    assert_equal BigDecimal("900000"), @account.reload.balance
  end

  test "creates and renames a pocket" do
    payload = invoke_tool(Mcp::Tools::Pockets::CreatePocketTool, user: @user, name: "Emergencias")
    assert_equal true, payload["success"]
    pocket_id = payload.dig("data", "id")

    payload = invoke_tool(Mcp::Tools::Pockets::UpdatePocketTool, user: @user,
                          pocket_id: pocket_id, name: "Fondo de emergencia", active: false)
    assert_equal true, payload["success"]
    pocket = MoneySource.find(pocket_id)
    assert_equal "Fondo de emergencia", pocket.name
    assert_not pocket.active?
  end
end
