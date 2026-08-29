# frozen_string_literal: true

require "test_helper"

class MoneySourceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Test User", email: "money_source_test@example.com", password: "password123")
  end

  def create_source(**overrides)
    @user.money_sources.create!(
      { name: "Savings Account", kind: "account", starting_balance: 1000 }.merge(overrides)
    )
  end

  test "is valid with required attributes" do
    source = MoneySource.new(user: @user, name: "My Account", kind: "account")
    assert source.valid?
  end

  test "name is required" do
    source = MoneySource.new(user: @user, kind: "account")
    assert_not source.valid?
    assert_includes source.errors[:name], I18n.t("errors.messages.blank")
  end

  test "kind is required and must be in KINDS" do
    source = MoneySource.new(user: @user, name: "Test")
    assert_not source.valid?
    assert_includes source.errors[:kind], I18n.t("errors.messages.blank")

    source.kind = "invalid"
    assert_not source.valid?
    assert_includes source.errors[:kind], I18n.t("errors.messages.inclusion")
  end

  test "kind is normalized to lowercase" do
    source = create_source(kind: "Account")
    assert_equal "account", source.kind
  end

  test "starting_balance defaults to 0" do
    source = MoneySource.new(user: @user, name: "Test", kind: "account")
    assert_equal BigDecimal("0"), source.starting_balance.to_d
  end

  test "valid KINDS are accepted" do
    MoneySource::KINDS.each do |kind|
      source = create_source(name: "Source #{kind}", kind: kind)
      assert source.persisted?, "expected #{kind} to be valid"
    end
  end

  test "active scope returns only active sources" do
    active = create_source(name: "Active", active: true)
    inactive = create_source(name: "Inactive", active: false)
    assert_includes MoneySource.active, active
    assert_not_includes MoneySource.active, inactive
  end

  test "by_kind scope filters by kind" do
    account = create_source(name: "Account", kind: "account")
    card = create_source(name: "Credit Card", kind: "credit_card")
    assert_includes MoneySource.by_kind("account"), account
    assert_not_includes MoneySource.by_kind("account"), card
  end

  test "balance includes starting_balance plus transactions" do
    source = create_source(starting_balance: 100)
    category = Category.create!(name: "Food")
    source.transactions.create!(user: @user, category: category, amount: -50, date: Date.today, kind: "expense", source: "manual")
    source.transactions.create!(user: @user, category: category, amount: 200, date: Date.today, kind: "income", source: "manual")
    assert_equal BigDecimal("250"), source.reload.balance
  end

  test "balance rolls up child card transactions for debit_card parent" do
    account = create_source(name: "Checking", kind: "account", starting_balance: 500)
    card = create_source(name: "Debit Card", kind: "debit_card", parent: account)
    category = Category.create!(name: "Food")
    card.transactions.create!(user: @user, category: category, amount: -30, date: Date.today, kind: "expense", source: "manual")
    assert_equal BigDecimal("470"), account.reload.balance
  end

  test "balance subtracts outgoing transfers" do
    source_a = create_source(name: "Savings", starting_balance: 1000)
    source_b = create_source(name: "Checking", starting_balance: 0)
    Transfer.create!(user: @user, from_source: source_a, to_source: source_b, amount: 200, date: Date.today)
    assert_equal BigDecimal("800"), source_a.reload.balance
  end

  test "balance adds incoming transfers" do
    source_a = create_source(name: "Savings", starting_balance: 1000)
    source_b = create_source(name: "Checking", starting_balance: 0)
    Transfer.create!(user: @user, from_source: source_a, to_source: source_b, amount: 200, date: Date.today)
    assert_equal BigDecimal("200"), source_b.reload.balance
  end

  test "credit_card balance is negative (debt)" do
    cc = create_source(name: "Visa", kind: "credit_card", starting_balance: 0)
    category = Category.create!(name: "Shopping")
    cc.transactions.create!(user: @user, category: category, amount: -150, date: Date.today, kind: "expense", source: "manual")
    assert_equal BigDecimal("-150"), cc.reload.balance
  end

  test "credit_card? and debit_card?" do
    cc = create_source(name: "Visa", kind: "credit_card")
    dc = create_source(name: "Debit", kind: "debit_card")
    assert cc.credit_card?
    assert_not cc.debit_card?
    assert dc.debit_card?
    assert_not dc.credit_card?
  end

  test "balance_label shows arrow for debit card with parent" do
    account = create_source(name: "Checking", kind: "account")
    card = create_source(name: "Debit", kind: "debit_card", parent: account)
    assert_equal "→ Checking", card.balance_label
  end

  test "balance_label shows formatted amount for non-debit-card" do
    source = create_source(starting_balance: 100)
    assert_match(/\$100/, source.balance_label)
  end

  test "display_name includes bank when present" do
    source = create_source(name: "My Account", bank: "Bancolombia")
    assert_equal "My Account · Bancolombia", source.display_name
  end

  test "display_name omits bank when blank" do
    source = create_source(name: "My Account")
    assert_equal "My Account", source.display_name
  end

  test "parent-child relationship" do
    account = create_source(name: "Checking", kind: "account")
    card = create_source(name: "Debit", kind: "debit_card", parent: account)
    assert_equal account, card.parent
    assert_includes account.children, card
  end

  test "destroying parent nullifies children parent_id" do
    account = create_source(name: "Checking", kind: "account")
    card = create_source(name: "Debit", kind: "debit_card", parent: account)
    account.destroy
    assert_nil card.reload.parent_id
  end
end
