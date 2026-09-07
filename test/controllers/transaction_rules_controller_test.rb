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
end