# frozen_string_literal: true

require "test_helper"

class TransactionRulesFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Test User",
      email: "transaction_rules_flow@example.com",
      password: "password123"
    )
    @fitness = Category.create!(name: "Fitness", is_default: true, category_type: "expense")
    @transport = Category.create!(name: "Transportation", is_default: true, category_type: "expense")
    @entertainment = Category.create!(name: "Entertainment", is_default: true, category_type: "expense")
    sign_in @user
  end

  def create_rule(**overrides)
    TransactionRule.create!(
      { user: @user, merchant_contains: "SMARTFIT", category_id: @fitness.id }.merge(overrides)
    )
  end

  test "index shows a summary line and rule cards" do
    create_rule
    get transaction_rules_path
    assert_response :success
    assert_select "h1", text: /Reglas/
    assert_select ".card-title", text: /SMARTFIT/
    assert_select ".badge.bg-success", text: /Habilitada/
    assert_match /reglas? habilitad/, response.body
  end

  test "index shows native suggestion from transaction history" do
    5.times do
      Expense.create!(user: @user, category: @fitness, amount: 50_000, date: Date.current,
                      description: "smartfit bogotá")
    end

    get transaction_rules_path
    assert_response :success
    assert_select "section#suggested-rules"
    assert_select "a.btn.btn-sm.btn-primary[href=?]",
                  new_transaction_rule_path(suggestion: "pattern", value: "smartfit bogotá", category_id: @fitness.id)
  end

  test "manual expense creation applies an automatic rule to a blank category" do
    create_rule
    post expenses_path, params: {
      expense: { description: "SMARTFIT Bogotá", amount: 50_000, date: "2026-09-01" }
    }
    assert_redirected_to expenses_path
    expense = Expense.last
    assert_equal @fitness.id, expense.category_id
    assert_includes expense.applied_rule_ids, TransactionRule.last.id
  end

  test "manual expense creation does not overwrite an explicit category" do
    create_rule
    post expenses_path, params: {
      expense: { description: "SMARTFIT Bogotá", amount: 50_000, date: "2026-09-01",
                 category_id: @transport.id }
    }
    expense = Expense.last
    assert_equal @transport.id, expense.category_id
  end

  test "Expenses::Create applies rules to imported transactions" do
    source = @user.money_sources.create!(name: "Nubank", kind: "credit_card", starting_balance: 0)
    create_rule(merchant_contains: "UBER", category_id: nil, action_money_source_id: source.id, tag: "Transport")

    expense = Expenses::Create.call(
      user: @user, amount: 20_000, description: "UBER Trip", category: @entertainment,
      occurred_at: Date.current, source: :csv
    )
    assert_equal @entertainment.id, expense.category_id
    assert_equal source.id, expense.money_source_id
    assert_includes expense.tags, "Transport"
    assert_includes expense.applied_rule_ids, TransactionRule.last.id
  end

  test "more specific rule wins over a generic description rule" do
    create_rule(merchant_contains: "UBER", category_id: @transport.id, priority: 5)
    create_rule(merchant_contains: nil, description_contains: "pago", category_id: @fitness.id, priority: 1)

    expense = Expense.create!(user: @user, description: "UBER pago", amount: 20_000, date: Date.current)

    assert_equal @transport.id, expense.category_id
  end

  test "gmail import path applies rules" do
    create_rule(merchant_contains: "NETFLIX", category_id: @entertainment.id)
    expense = Expense.create!(user: @user, description: "NETFLIX", amount: 35_000, date: Date.current, source: "gmail")
    assert_equal @entertainment.id, expense.category_id
  end

  test "manual edits are never clobbered after a rule applied" do
    rule = create_rule
    expense = Expense.create!(user: @user, description: "SMARTFIT", amount: 50_000, date: Date.current)
    assert_equal @fitness.id, expense.category_id

    patch expense_path(expense), params: { expense: { category_id: @entertainment.id } }
    assert_equal @entertainment.id, expense.reload.category_id
  end

  test "index shows a Dismiss button next to each suggestion" do
    5.times do
      Expense.create!(user: @user, category: @fitness, amount: 50_000, date: Date.current,
                      description: "smartfit bogotá")
    end

    get transaction_rules_path
    assert_response :success
    assert_select "section#suggested-rules form[action*=?]",
                  dismiss_suggestion_transaction_rules_path, minimum: 1
    assert_select "section#suggested-rules button", text: /Descartar/, minimum: 1
  end

  test "dismissing a suggestion removes it from the index" do
    5.times do
      Expense.create!(user: @user, category: @fitness, amount: 50_000, date: Date.current,
                      description: "smartfit bogotá")
    end

    post dismiss_suggestion_transaction_rules_path, params: { merchant: "smartfit bogotá" }
    assert_redirected_to transaction_rules_path

    get transaction_rules_path
    assert_response :success
    assert_select "section#suggested-rules", count: 0
  end

  test "creating a rule from a suggestion makes the suggestion disappear" do
    5.times do
      Expense.create!(user: @user, category: @fitness, amount: 50_000, date: Date.current,
                      description: "smartfit bogotá")
    end

    post transaction_rules_path, params: {
      transaction_rule: { merchant_contains: "smartfit bogotá", category_id: @fitness.id }
    }
    assert_redirected_to transaction_rules_path

    get transaction_rules_path
    assert_response :success
    assert_select "section#suggested-rules", count: 0
    assert_select ".card-title", text: /smartfit bogotá/
  end

  test "index shows the rules navigation in the sidebar" do
    get transaction_rules_path
    assert_response :success
    assert_select ".sidebar-link[href=?]", transaction_rules_path, text: /Reglas/
  end
end