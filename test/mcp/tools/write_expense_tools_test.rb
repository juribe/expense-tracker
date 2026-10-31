# frozen_string_literal: true

require "test_helper"
require_relative "../../support/mcp_tool_helper"

class WriteExpenseToolsTest < ActiveSupport::TestCase
  include McpToolHelper

  setup do
    @user = User.create!(name: "MCP Write Expenses", email: "mcp_write_expenses@example.com", password: "password123")
    @other_user = User.create!(name: "Other", email: "mcp_write_expenses_other@example.com", password: "password123")
    @category = Category.create!(name: "Transporte Escritura", is_default: true, category_type: "expense")
    @income_category = Category.create!(name: "Ingreso Escritura", is_default: true, category_type: "income")
    @account = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 1_000_000)
    @pocket = @user.money_sources.create!(name: "Bolsa", kind: "pocket", starting_balance: 100_000)
    @token, = McpAccessToken.issue!(user: @user, name: "Writer", scopes: [ :read, :write ])

    @foreign_expense = Expense.create!(
      user: @other_user,
      category: @category,
      money_source: @other_user.money_sources.create!(name: "Ajena", kind: "account", starting_balance: 100_000),
      amount: 10_000, date: Date.current, description: "Ajena"
    )
  end

  test "creates an expense and moves the money source balance" do
    payload = invoke_tool(
      Mcp::Tools::Expenses::CreateExpenseTool, user: @user, token: @token,
      amount: "85000", date: Date.current.iso8601, category_id: @category.id,
      money_source_id: @account.id, description: "Gasolina"
    )

    assert_equal true, payload["success"]
    expense = Expense.find(payload.dig("data", "id"))
    assert_equal BigDecimal("-85000"), expense.amount
    assert_equal "manual", expense.source
    assert_equal "Gasolina", expense.description
    assert_equal BigDecimal("915000"), @account.reload.balance
    assert_equal "85000.0", payload.dig("data", "amount")
  end

  test "rejects a category of another user" do
    foreign_category = Category.create!(name: "Privada", user: @other_user, category_type: "expense")

    assert_no_difference "Expense.count" do
      payload = invoke_tool(
        Mcp::Tools::Expenses::CreateExpenseTool, user: @user,
        amount: "1000", date: Date.current.iso8601, category_id: foreign_category.id,
        money_source_id: @account.id, description: "X"
      )

      assert_equal false, payload["success"]
      assert_equal "INVALID_CATEGORY", payload.dig("error", "code")
    end
  end

  test "rejects a pocket as the payment source" do
    payload = invoke_tool(
      Mcp::Tools::Expenses::CreateExpenseTool, user: @user,
      amount: "1000", date: Date.current.iso8601, category_id: @category.id,
      money_source_id: @pocket.id, description: "X"
    )

    assert_equal false, payload["success"]
    assert_equal "INVALID_MONEY_SOURCE", payload.dig("error", "code")
  end

  test "rejects an expense above the available balance" do
    assert_no_difference "Expense.count" do
      payload = invoke_tool(
        Mcp::Tools::Expenses::CreateExpenseTool, user: @user,
        amount: "2000000", date: Date.current.iso8601, category_id: @category.id,
        money_source_id: @account.id, description: "X"
      )

      assert_equal false, payload["success"]
      assert_equal "INSUFFICIENT_FUNDS", payload.dig("error", "code")
    end
  end

  test "is idempotent for the same key and arguments" do
    key = SecureRandom.uuid
    arguments = {
      amount: "50000", date: Date.current.iso8601, category_id: @category.id,
      money_source_id: @account.id, description: "Café", idempotency_key: key
    }

    first = invoke_tool(Mcp::Tools::Expenses::CreateExpenseTool, user: @user, **arguments)
    assert_equal true, first["success"]

    assert_no_difference "Expense.count" do
      second = invoke_tool(Mcp::Tools::Expenses::CreateExpenseTool, user: @user, **arguments)
      assert_equal true, second["success"]
      assert_equal first.dig("data", "id"), second.dig("data", "id")
    end
  end

  test "rejects a reused idempotency key with different arguments" do
    key = SecureRandom.uuid
    invoke_tool(Mcp::Tools::Expenses::CreateExpenseTool, user: @user, amount: "10000",
                date: Date.current.iso8601, category_id: @category.id,
                money_source_id: @account.id, description: "A", idempotency_key: key)

    payload = invoke_tool(Mcp::Tools::Expenses::CreateExpenseTool, user: @user, amount: "20000",
                          date: Date.current.iso8601, category_id: @category.id,
                          money_source_id: @account.id, description: "A", idempotency_key: key)

    assert_equal false, payload["success"]
    assert_equal "CONFLICT_DUPLICATE", payload.dig("error", "code")
  end

  test "updates an expense and resyncs the balance" do
    expense = Expense.create!(user: @user, category: @category, money_source: @account,
                              amount: 100_000, date: Date.current, description: "Viejo")

    payload = invoke_tool(Mcp::Tools::Expenses::UpdateExpenseTool, user: @user, expense_id: expense.id,
                          amount: "60000", description: "Corregido")

    assert_equal true, payload["success"]
    assert_equal BigDecimal("-60000"), expense.reload.amount
    assert_equal "Corregido", expense.description
    assert_equal BigDecimal("940000"), @account.reload.balance
  end

  test "does not update another user's expense" do
    payload = invoke_tool(Mcp::Tools::Expenses::UpdateExpenseTool, user: @user,
                          expense_id: @foreign_expense.id, description: "Hack")

    assert_equal false, payload["success"]
    assert_equal "NOT_FOUND", payload.dig("error", "code")
  end

  test "requires explicit confirmation before deleting" do
    expense = Expense.create!(user: @user, category: @category, money_source: @account,
                              amount: 10_000, date: Date.current, description: "Borrar")

    assert_no_difference "Expense.count" do
      payload = invoke_tool(Mcp::Tools::Expenses::DeleteExpenseTool, user: @user, expense_id: expense.id)
      assert_equal false, payload["success"]
      assert_equal "OPERATION_NOT_ALLOWED", payload.dig("error", "code")
    end

    assert_difference "Expense.count", -1 do
      payload = invoke_tool(Mcp::Tools::Expenses::DeleteExpenseTool, user: @user,
                            expense_id: expense.id, confirm: true)
      assert_equal true, payload["success"]
    end
  end

  test "records an audit entry without the argument values" do
    invoke_tool(Mcp::Tools::Expenses::CreateExpenseTool, user: @user, token: @token,
                amount: "85000", date: Date.current.iso8601, category_id: @category.id,
                money_source_id: @account.id, description: "Gasolina")

    audit = McpToolInvocation.where(tool_name: "create_expense").last
    assert_equal "succeeded", audit.status
    assert_equal @user.id, audit.user_id
    assert_equal @token.id, audit.mcp_access_token_id
    assert_includes audit.argument_keys, "amount"
    assert_not audit.attributes.values.map(&:to_s).any? { |value| value.include?("Gasolina") }
  end
end
