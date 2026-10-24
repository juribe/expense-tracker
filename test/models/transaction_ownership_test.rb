# frozen_string_literal: true

require "test_helper"

# A transaction may only reference the user's own money sources and custom
# categories; shared default categories remain available to every user.
class TransactionOwnershipTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Owner", email: "transaction_ownership@example.com", password: "password123")
    @other_user = User.create!(name: "Other", email: "transaction_ownership_other@example.com", password: "password123")
    @source = @user.money_sources.create!(name: "Ahorros", kind: "account", starting_balance: 100_000)
    @other_source = @other_user.money_sources.create!(name: "Ajena", kind: "account", starting_balance: 100_000)
    @default_category = Category.create!(name: "Alimentación", is_default: true, category_type: "expense")
    @other_category = Category.create!(name: "Privada Ajena", user: @other_user, is_default: false,
                                       category_type: "expense")
  end

  def expense(**overrides)
    Expense.new({
      user: @user, amount: 10_000, description: "Almuerzo", date: Date.current,
      category: @default_category, money_source: @source
    }.merge(overrides))
  end

  test "an expense with another user's money source is invalid" do
    record = expense(money_source: @other_source)
    balance_before = @other_source.reload.cached_balance

    assert_not record.valid?
    assert_includes record.errors[:money_source], I18n.t("activerecord.errors.messages.other_user")
    assert_equal balance_before, @other_source.reload.cached_balance
  end

  test "an income with another user's money source is invalid" do
    income = Income.new(user: @user, amount: 100_000, description: "Salario", date: Date.current,
                        money_source: @other_source)

    assert_not income.valid?
    assert_includes income.errors[:money_source], I18n.t("activerecord.errors.messages.other_user")
  end

  test "an expense with another user's custom category is invalid" do
    record = expense(category: @other_category)

    assert_not record.valid?
    assert_includes record.errors[:category], I18n.t("activerecord.errors.messages.other_user")
  end

  test "a default category remains available to every user" do
    assert expense.valid?

    income_category = Category.create!(name: "Salario Default", is_default: true, category_type: "income")
    income = Income.new(user: @user, amount: 100_000, description: "Salario", date: Date.current,
                        category: income_category, money_source: @source)

    assert income.valid?
  end

  test "a shared category without an owner remains available" do
    shared_category = Category.create!(name: "Compartida", is_default: false, category_type: "expense")

    assert expense(category: shared_category).valid?
  end

  test "the user's own custom category is valid" do
    own_category = Category.create!(name: "Propia", user: @user, is_default: false, category_type: "expense")

    assert expense(category: own_category).valid?
  end

  test "updating an expense to another user's money source is invalid" do
    record = expense
    record.save!

    record.money_source = @other_source

    assert_not record.valid?
    assert_includes record.errors[:money_source], I18n.t("activerecord.errors.messages.other_user")
  end
end
