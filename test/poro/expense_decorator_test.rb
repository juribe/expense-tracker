# frozen_string_literal: true

require "test_helper"

class ExpenseDecoratorTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Deco User", email: "decorator@example.com", password: "password123")
    @category = Category.create!(name: "Comida", user: @user, is_default: false, category_type: "expense")
    @account = MoneySource.create!(user: @user, name: "Cuenta", kind: "account")
  end

  test "delegates attribute access to the wrapped expense" do
    expense = create_expense(description: "Almuerzo")
    decorated = ExpenseDecorator.new(expense)

    assert_equal "Almuerzo", decorated.description
    assert_equal expense.id, decorated.id
    assert_equal expense.amount, decorated.amount
  end

  test "description_or_fallback replaces blank descriptions" do
    blank = ExpenseDecorator.new(create_expense(description: nil))
    present = ExpenseDecorator.new(create_expense(description: "Cena"))

    assert_equal I18n.t("expenses.no_description"), blank.description_or_fallback
    assert_equal "Cena", present.description_or_fallback
  end

  test "lowercase_description provides the aria-safe lowercase text" do
    decorated = ExpenseDecorator.new(create_expense(description: "Didi Viaje"))

    assert_equal "didi viaje", decorated.lowercase_description
  end

  test "source_name falls back to empty string" do
    with_source = ExpenseDecorator.new(create_expense(money_source: @account))
    without_source = ExpenseDecorator.new(create_expense(money_source: nil))

    assert_equal "Cuenta", with_source.source_name
    assert_equal "", without_source.source_name
  end

  test "wrapped? helpers expose category and recurring state" do
    decorated = ExpenseDecorator.new(create_expense(category: @category, recurring_template_id: nil))
    template = @user.recurring_templates.create!(
      category: @category, kind: "expense", amount: 10_000,
      description: "Arriendo", payment_day: 5, source: "manual"
    )
    linked = ExpenseDecorator.new(create_expense(recurring_template_id: template.id))

    assert_not_nil decorated.category
    assert_not decorated.recurring_linked?
    assert linked.recurring_linked?
  end

  def create_expense(**overrides)
    Expense.create!(
      {
        user: @user, category: @category, amount: 10_000, description: "Gasto",
        date: Date.current, source: "manual", money_source: @account
      }.merge(overrides)
    )
  end
end
