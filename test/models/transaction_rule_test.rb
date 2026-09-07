# frozen_string_literal: true

require "test_helper"

class TransactionRuleTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Test User", email: "rule_test@example.com", password: "password123")
    @fitness = Category.create!(name: "Fitness", is_default: true, category_type: "expense")
    @transport = Category.create!(name: "Transportation", is_default: true, category_type: "expense")
    @entertainment = Category.create!(name: "Entertainment", is_default: true, category_type: "expense")
  end

  def create_rule(**overrides)
    TransactionRule.create!(
      { user: @user, merchant_contains: "SMARTFIT", category_id: @fitness.id }.merge(overrides)
    )
  end

  def create_expense(description:, category: @transport, amount: 50_000, user: @user, money_source: nil)
    Expense.create!(user: user, category: category, amount: amount, date: Date.current,
                    description: description, money_source: money_source)
  end

  test "is valid with a condition and an action" do
    assert create_rule.valid?
  end

  test "requires at least one condition" do
    rule = TransactionRule.new(user: @user, category_id: @fitness.id)
    assert_not rule.valid?
    assert_includes rule.errors[:base], I18n.t("transaction_rules.validation.at_least_one_condition")
  end

  test "requires at least one action" do
    rule = TransactionRule.new(user: @user, merchant_contains: "SMARTFIT")
    assert_not rule.valid?
    assert_includes rule.errors[:base], I18n.t("transaction_rules.validation.at_least_one_action")
  end

  test "belongs to the user" do
    rule = TransactionRule.new(merchant_contains: "SMARTFIT", category_id: @fitness.id)
    assert_not rule.valid?
    assert rule.errors[:user].any?
  end

  test "enabled defaults to true" do
    assert create_rule.enabled?
  end

  test "active scope returns only enabled rules" do
    enabled = create_rule
    disabled = create_rule(merchant_contains: "UBER", enabled: false)
    assert_includes TransactionRule.active, enabled
    assert_not_includes TransactionRule.active, disabled
  end

  test "for_user scope returns only the user's rules" do
    mine = create_rule
    other_user = User.create!(name: "Other", email: "rule_other@example.com", password: "password123")
    theirs = TransactionRule.create!(user: other_user, merchant_contains: "OTHER", category_id: @transport.id)
    assert_includes TransactionRule.for_user(@user), mine
    assert_not_includes TransactionRule.for_user(@user), theirs
  end

  test "title uses the name when present" do
    rule = create_rule(name: "Gym")
    assert_equal "Gym", rule.title
  end

  test "title falls back to the merchant condition" do
    assert_equal "SMARTFIT", create_rule.title
  end

  # --- matching ---

  test "matches a merchant contained in the transaction description" do
    rule = create_rule
    transaction = create_expense(description: "SMARTFIT Bogotá")
    assert rule.matches?(transaction)
  end

  test "merchant matching is case-insensitive" do
    rule = create_rule
    transaction = create_expense(description: "smartfit Cali")
    assert rule.matches?(transaction)
  end

  test "does not match a different merchant" do
    rule = create_rule
    transaction = create_expense(description: "UBER Trip")
    assert_not rule.matches?(transaction)
  end

  test "matches on description contains" do
    rule = create_rule(merchant_contains: nil, description_contains: "Suscripción", category_id: @entertainment.id)
    transaction = create_expense(description: "NETFLIX Suscripción mensual")
    assert rule.matches?(transaction)
  end

  test "disabled rules never match" do
    rule = create_rule(enabled: false)
    transaction = create_expense(description: "SMARTFIT")
    assert_not rule.matches?(transaction)
  end

  test "amount greater than matches on absolute amount" do
    rule = create_rule(merchant_contains: nil, amount_gt: 100, category_id: @fitness.id)
    assert rule.matches?(create_expense(description: "Big expense", amount: 200))
    assert_not rule.matches?(create_expense(description: "Small expense", amount: 50))
  end

  test "amount less than matches on absolute amount" do
    rule = create_rule(merchant_contains: nil, amount_lt: 100, category_id: @fitness.id)
    assert rule.matches?(create_expense(description: "Small expense", amount: 50))
    assert_not rule.matches?(create_expense(description: "Big expense", amount: 200))
  end

  test "money source condition matches the transaction's source" do
    source = @user.money_sources.create!(name: "Nubank", kind: "credit_card", starting_balance: 0)
    other_source = @user.money_sources.create!(name: "Bancolombia", kind: "account", starting_balance: 0)
    rule = create_rule(merchant_contains: nil, money_source_condition: source, category_id: @fitness.id)

    matching = create_expense(description: "Gym", money_source: source)
    non_matching = create_expense(description: "Gym", money_source: other_source)

    assert rule.matches?(matching)
    assert_not rule.matches?(non_matching)
  end

  # --- actions ---

  test "applying a rule fills a blank category and records rule_id" do
    rule = create_rule
    transaction = Expense.new(user: @user, amount: 50_000, date: Date.current, description: "SMARTFIT Bogotá")
    rule.apply_to(transaction)
    assert_equal @fitness.id, transaction.category_id
    assert_equal rule.id, transaction.rule_id
    assert_includes transaction.applied_rule_ids, rule.id
  end

  test "applying a rule does not overwrite an existing category" do
    rule = create_rule
    transaction = create_expense(description: "SMARTFIT", category: @transport)
    rule.apply_to(transaction)
    assert_equal @transport.id, transaction.category_id
    assert_not_includes transaction.applied_rule_ids, rule.id
  end

  test "tag action adds a tag when missing" do
    rule = create_rule(category_id: nil, tag: "Subscriptions")
    transaction = Expense.new(user: @user, description: "NETFLIX", amount: 20_000, date: Date.current)
    rule.apply_to(transaction)
    assert_includes transaction.tags, "Subscriptions"
  end

  test "tag action does not duplicate an existing tag" do
    rule = create_rule(category_id: nil, tag: "Subscriptions")
    transaction = Expense.new(user: @user, description: "NETFLIX", amount: 20_000, date: Date.current)
    transaction.tags = [ "Subscriptions" ]
    rule.apply_to(transaction)
    assert_equal [ "Subscriptions" ], transaction.tags
  end

  # --- duplicate application prevention ---

  test "a rule already applied to a transaction is not applied again" do
    rule = create_rule
    transaction = Expense.new(user: @user, description: "SMARTFIT", amount: 50_000, date: Date.current,
                              category: @fitness, applied_rule_ids: [ rule.id ])
    before = transaction.applied_rule_ids.dup
    rule.apply_to(transaction)
    assert_equal before, transaction.applied_rule_ids
  end

  # --- precedence ---

  test "ordered_by_specificity ranks amount rules over merchant rules" do
    amount_rule = create_rule(merchant_contains: nil, amount_gt: 100, priority: 0)
    merchant_rule = create_rule(merchant_contains: "SMARTFIT", priority: 5)
    assert_equal [ amount_rule, merchant_rule ], TransactionRule.active.ordered_by_specificity.to_a
  end

  test "ordered_by_specificity ranks merchant rules over description rules" do
    merchant_rule = create_rule(merchant_contains: "SMARTFIT")
    desc_rule = create_rule(merchant_contains: nil, description_contains: "pago")
    assert_equal [ merchant_rule, desc_rule ], TransactionRule.active.ordered_by_specificity.to_a
  end

  test "ordered_by_specificity breaks ties within a tier by priority" do
    lower = create_rule(merchant_contains: "SMARTFIT", priority: 1)
    higher = create_rule(merchant_contains: "UBER", priority: 10)
    assert_equal [ higher, lower ], TransactionRule.active.ordered_by_specificity.to_a
  end

  test "applicator fills gaps then respects manual overrides" do
    rule = create_rule
    source = @user.money_sources.create!(name: "Nubank", kind: "credit_card", starting_balance: 0)
    manual_tx = Expense.create!(user: @user, description: "SMARTFIT", amount: 50_000, date: Date.current,
                                category: @transport, money_source: source)
    assert_equal @transport.id, manual_tx.category_id
    assert_equal source.id, manual_tx.money_source_id
    assert_empty manual_tx.applied_rule_ids
  end

  test "applicator applies a rule to gmail-imported transactions once" do
    rule = create_rule
    expense = Expense.create!(user: @user, description: "SMARTFIT", amount: 50_000, date: Date.current,
                              source: "gmail")
    assert_equal @fitness.id, expense.category_id
    assert_includes expense.applied_rule_ids, rule.id

    expense.update!(description: "SMARTFIT again")
    assert_equal [ rule.id ], expense.applied_rule_ids
  end
end