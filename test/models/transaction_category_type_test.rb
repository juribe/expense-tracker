# frozen_string_literal: true

require "test_helper"

class TransactionCategoryTypeTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Category Type", email: "category_type_rule@example.com", password: "password123")
    @source = @user.money_sources.create!(name: "Ahorros", kind: "account", starting_balance: 1_000_000)
    @expense_category = Category.create!(name: "Mercado", user: @user, is_default: false, category_type: "expense")
    @income_category = Category.create!(name: "Salario", user: @user, is_default: false, category_type: "income")
  end

  test "an expense cannot be created with an income category" do
    expense = build_transaction(kind: "expense", category: @income_category)

    assert_not expense.valid?
    assert_includes expense.errors[:category_id], I18n.t("validation.category_type_mismatch")
  end

  test "an income cannot be created with an expense category" do
    income = build_transaction(kind: "income", category: @expense_category)

    assert_not income.valid?
    assert_includes income.errors[:category_id], I18n.t("validation.category_type_mismatch")
  end

  test "a transaction can be created with a matching category type" do
    expense = build_transaction(kind: "expense", category: @expense_category)
    income = build_transaction(kind: "income", category: @income_category)

    assert expense.valid?
    assert income.valid?
  end

  test "a transaction can be created with an untyped category" do
    untyped = Category.create!(name: "Otros", user: @user, is_default: false, category_type: nil)
    expense = build_transaction(kind: "expense", category: untyped)

    assert expense.valid?
  end

  test "a transaction can be created without a category" do
    expense = build_transaction(kind: "expense", category: nil)

    assert expense.valid?
  end

  test "the rule is not enforced when updating an existing transaction" do
    expense = @user.expenses.create!(amount: 50_000, description: "Almuerzo", date: Date.current,
                                     kind: "expense", source: "manual", money_source: @source,
                                     category: @expense_category)

    expense.update!(category: @income_category)

    assert_equal @income_category, expense.reload.category
  end

  private

  def build_transaction(kind:, category:)
    Transaction.new(user: @user, amount: 50_000, description: "Movimiento", date: Date.current,
                    kind: kind, source: "manual", money_source: @source, category: category)
  end
end
