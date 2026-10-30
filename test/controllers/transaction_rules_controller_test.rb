# frozen_string_literal: true

require "test_helper"

class TransactionRulesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Test User",
      email: "transaction_rules_controller@example.com",
      password: "password123"
    )
    @category = Category.create!(name: "Fitness", is_default: true, category_type: "expense")
    @other_category = Category.create!(name: "Transportation", is_default: true, category_type: "expense")
    sign_in @user
  end

  def create_rule(**overrides)
    TransactionRule.create!(
      { user: @user, merchant_contains: "SMARTFIT", category_id: @category.id }.merge(overrides)
    )
  end

  test "GET /transaction_rules renders the index" do
    rule = create_rule
    get transaction_rules_path
    assert_response :success
    assert_select "h1", text: /Reglas/
    assert_select "a[href=?]", new_transaction_rule_path
    assert_select "a[href=?]", edit_transaction_rule_path(rule)
    assert_select "div.d-inline-flex a.btn-sm.btn-outline-primary", count: 1
    assert_select "div.d-inline-flex form button.btn-sm.btn-outline-danger", count: 1
  end

  test "GET /transaction_rules/new renders the form" do
    get new_transaction_rule_path
    assert_response :success
    assert_select "form"
    assert_select "#transaction_rule_merchant_contains"
  end

  test "GET /transaction_rules/new prefills from a suggested rule" do
    get new_transaction_rule_path(suggestion: "pattern", value: "smartfit", category_id: @category.id)
    assert_response :success
    assert_select "input#transaction_rule_merchant_contains[value='smartfit']"
    assert_select "select#transaction_rule_category_id option[value=?][selected='selected']", @category.id.to_s
    assert_select "[data-testid=transaction-rule-category-picker] [role=combobox]"
    assert_select "[data-testid=transaction-rule-category-picker] [role=option][data-value=?][aria-selected=true]",
                  @category.id.to_s
  end

  test "GET /transaction_rules/new and edit render the shared card header and footer" do
    rule = create_rule

    get new_transaction_rule_path
    assert_response :success
    assert_select "form[action='#{transaction_rules_path}'] .card" do
      assert_select ".card-header .icon-chip i.ti-wand"
      assert_select ".card-header h4", text: "Nueva regla"
      assert_select ".card-header .card-subtitle", text: /Aplica categorías o fuentes/
      assert_select ".card-footer a.btn.btn-outline-secondary[href=?]", transaction_rules_path, text: "Cancelar"
      assert_select ".card-footer input[type=submit].btn.btn-primary[value='Guardar regla']"
    end

    get edit_transaction_rule_path(rule)
    assert_response :success
    assert_select "form[action='#{transaction_rule_path(rule)}'] .card .card-header h4", text: "Editar regla"
    assert_select "form[action='#{transaction_rule_path(rule)}'] .card .card-footer input[type=submit].btn.btn-primary[value='Guardar cambios']"
  end

  test "POST /transaction_rules creates a rule for the current user" do
    assert_difference("TransactionRule.count", 1) do
      post transaction_rules_path, params: {
        transaction_rule: { merchant_contains: "SMARTFIT", category_id: @category.id }
      }
    end
    rule = TransactionRule.last
    assert_equal @user, rule.user
    assert_equal "SMARTFIT", rule.merchant_contains
    assert_equal @category.id, rule.category_id
    assert rule.enabled?
    assert_redirected_to transaction_rules_path
    assert_equal I18n.t("transaction_rules.flashes.created"), flash[:notice]
  end

  test "POST /transaction_rules with invalid params re-renders the form" do
    assert_no_difference("TransactionRule.count") do
      post transaction_rules_path, params: { transaction_rule: { merchant_contains: "", category_id: nil } }
    end
    assert_response :unprocessable_entity
  end

  test "GET /transaction_rules/:id/edit renders the form for the user's rule" do
    rule = create_rule
    get edit_transaction_rule_path(rule)
    assert_response :success
    assert_select "form"
    assert_select "input#transaction_rule_merchant_contains[value='SMARTFIT']"
  end

  test "PATCH /transaction_rules/:id updates the rule" do
    rule = create_rule
    patch transaction_rule_path(rule), params: {
      transaction_rule: { merchant_contains: "UBER", category_id: @other_category.id }
    }
    assert_equal "UBER", rule.reload.merchant_contains
    assert_equal @other_category.id, rule.reload.category_id
    assert_redirected_to transaction_rules_path
    assert_equal I18n.t("transaction_rules.flashes.updated"), flash[:notice]
  end

  test "PATCH /transaction_rules/:id with invalid params re-renders the form" do
    rule = create_rule
    assert_no_difference("TransactionRule.count") do
      patch transaction_rule_path(rule), params: { transaction_rule: { merchant_contains: "", category_id: nil } }
    end
    assert_response :unprocessable_entity
  end

  test "DELETE /transaction_rules/:id destroys the rule" do
    rule = create_rule
    assert_difference("TransactionRule.count", -1) do
      delete transaction_rule_path(rule)
    end
    assert_redirected_to transaction_rules_path
    assert_equal I18n.t("transaction_rules.flashes.destroyed"), flash[:notice]
  end

  test "PATCH /transaction_rules/:id/toggle_active toggles the enabled flag" do
    rule = create_rule(enabled: true)
    patch toggle_active_transaction_rule_path(rule)
    assert_not rule.reload.enabled?
    patch toggle_active_transaction_rule_path(rule)
    assert rule.reload.enabled?
  end

  test "POST /transaction_rules/dismiss_suggestion persists the merchant dismissal" do
    post dismiss_suggestion_transaction_rules_path, params: { merchant: "smartfit bogotá" }
    assert_redirected_to transaction_rules_path
    assert_equal I18n.t("transaction_rules.flashes.suggestion_dismissed"), flash[:notice]
    assert_includes @user.reload.dismissed_rule_suggestions, "smartfit bogotá"
  end

  test "POST /transaction_rules/dismiss_suggestion normalizes and deduplicates merchants" do
    post dismiss_suggestion_transaction_rules_path, params: { merchant: "Smartfit Bogotá" }
    post dismiss_suggestion_transaction_rules_path, params: { merchant: "SMARTFIT BOGOTÁ" }
    assert_equal [ "smartfit bogotá" ], @user.reload.dismissed_rule_suggestions
  end

  test "POST /transaction_rules/dismiss_suggestion with a blank merchant does not add a dismissal" do
    post dismiss_suggestion_transaction_rules_path, params: { merchant: "  " }
    assert_redirected_to transaction_rules_path
    assert_empty @user.reload.dismissed_rule_suggestions
  end

  test "index hides suggestions whose merchant has been dismissed" do
    source = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 1_000_000)
    5.times do
      Expense.create!(user: @user, category: @category, amount: 50_000, date: Date.current,
                      description: "smartfit bogotá", money_source: source)
    end
    @user.update!(dismissed_rule_suggestions: [ "smartfit bogotá" ])

    get transaction_rules_path
    assert_response :success
    assert_select "section#suggested-rules", count: 0
  end

  test "PATCH /transaction_rules/:id clears the old condition when changing condition type" do
    rule = create_rule
    patch transaction_rule_path(rule), params: {
      condition_field: "description_contains",
      transaction_rule: { description_contains: "renta", category_id: @category.id }
    }
    assert_redirected_to transaction_rules_path
    rule = rule.reload
    assert_equal "renta", rule.description_contains
    assert_nil rule.merchant_contains
  end

  test "PATCH /transaction_rules/:id keeps the condition when the type is unchanged" do
    rule = create_rule
    patch transaction_rule_path(rule), params: {
      condition_field: "merchant_contains",
      transaction_rule: { merchant_contains: "SMARTFIT PLUS", category_id: @category.id }
    }
    assert_redirected_to transaction_rules_path
    rule = rule.reload
    assert_equal "SMARTFIT PLUS", rule.merchant_contains
    assert_nil rule.description_contains
  end

  test "PATCH /transaction_rules/:id clears the old action when changing action type" do
    rule = create_rule
    patch transaction_rule_path(rule), params: {
      condition_field: "merchant_contains",
      action_field: "tag",
      transaction_rule: { merchant_contains: "SMARTFIT", tag: "Fitness", category_id: nil }
    }
    assert_redirected_to transaction_rules_path
    rule = rule.reload
    assert_equal "Fitness", rule.tag
    assert_nil rule.category_id
  end

  test "PATCH /transaction_rules/:id keeps the action when the type is unchanged" do
    rule = create_rule
    patch transaction_rule_path(rule), params: {
      condition_field: "merchant_contains",
      action_field: "category",
      transaction_rule: { merchant_contains: "SMARTFIT", category_id: @other_category.id }
    }
    assert_redirected_to transaction_rules_path
    rule = rule.reload
    assert_equal @other_category.id, rule.category_id
    assert_nil rule.tag
  end

  test "POST /transaction_rules clears unselected condition and action fields" do
    post transaction_rules_path, params: {
      condition_field: "amount_gt",
      action_field: "tag",
      transaction_rule: { amount_gt: "10000", tag: "Big", category_id: @category.id }
    }
    assert_redirected_to transaction_rules_path
    rule = TransactionRule.last
    assert_equal "10000".to_d, rule.amount_gt
    assert_equal "Big", rule.tag
    assert_nil rule.category_id
    assert_nil rule.merchant_contains
  end

  test "cannot edit another user's rule" do
    other_user = User.create!(name: "Other", email: "rules_other@example.com", password: "password123")
    other_rule = TransactionRule.create!(user: other_user, merchant_contains: "OTHER", category_id: @category.id)
    get edit_transaction_rule_path(other_rule)
    assert_redirected_to transaction_rules_path
    assert_equal I18n.t("transaction_rules.not_found"), flash[:alert]
  end

  test "cannot delete another user's rule" do
    other_user = User.create!(name: "Other", email: "rules_other_delete@example.com", password: "password123")
    other_rule = TransactionRule.create!(user: other_user, merchant_contains: "OTHER", category_id: @category.id)
    assert_no_difference("TransactionRule.count") do
      delete transaction_rule_path(other_rule)
    end
    assert_redirected_to transaction_rules_path
    assert_equal I18n.t("transaction_rules.not_found"), flash[:alert]
  end

  test "POST /transaction_rules rejects a foreign category" do
    other_user = User.create!(name: "Other", email: "rules_foreign_category@example.com", password: "password123")
    foreign_category = Category.create!(name: "Ajena Rules", is_default: false, category_type: "expense",
                                        user: other_user)

    assert_no_difference "TransactionRule.count" do
      post transaction_rules_path, params: {
        transaction_rule: { merchant_contains: "AJENA", category_id: foreign_category.id }
      }
    end

    assert_response :unprocessable_entity
  end

  test "POST /transaction_rules rejects foreign money sources" do
    other_user = User.create!(name: "Other", email: "rules_foreign_source@example.com", password: "password123")
    foreign_source = other_user.money_sources.create!(name: "Cuenta Ajena", kind: "account")
    foreign_source_two = other_user.money_sources.create!(name: "Tarjeta Ajena", kind: "credit_card")

    assert_no_difference "TransactionRule.count" do
      post transaction_rules_path, params: {
        transaction_rule: { merchant_contains: "X", money_source_condition_id: foreign_source.id,
                            action_money_source_id: foreign_source_two.id }
      }
    end

    assert_response :unprocessable_entity
  end

  test "POST /transaction_rules accepts shared category with own money sources" do
    own_account = @user.money_sources.create!(name: "Cuenta Propia", kind: "account")
    own_card = @user.money_sources.create!(name: "Tarjeta Propia", kind: "credit_card")

    assert_difference "TransactionRule.count", 1 do
      post transaction_rules_path, params: {
        transaction_rule: { merchant_contains: "NETFLIX", category_id: @category.id,
                            money_source_condition_id: own_card.id, action_money_source_id: own_account.id }
      }
    end

    rule = TransactionRule.last
    assert_equal @category, rule.category
    assert_equal own_card, rule.money_source_condition
    assert_equal own_account, rule.action_money_source
    assert_redirected_to transaction_rules_path
  end
end