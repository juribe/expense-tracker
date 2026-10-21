# frozen_string_literal: true

require "test_helper"

# The money source is mandatory on every real transaction (expense or
# income): money always leaves from or arrives to a known source. Recurring
# templates stay optional — they are reminders; the rule applies to the
# real Transactions the Pay/Receive action creates.
class TransactionMoneySourceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Source Rule", email: "money_source_rule@example.com", password: "password123")
    @source = @user.money_sources.create!(name: "Ahorros", kind: "account", starting_balance: 1_000_000)
  end

  test "an expense without a money source is rejected" do
    expense = Expense.new(user: @user, amount: 50_000, description: "Almuerzo", date: Date.current,
                          kind: "expense", source: "manual", money_source: nil)

    assert_not expense.valid?
    assert_includes expense.errors[:money_source], I18n.t("activerecord.errors.messages.money_source_required")
  end

  test "an income without a money source is rejected" do
    income = Income.new(user: @user, amount: 200_000, description: "Salario", date: Date.current,
                        kind: "income", source: "manual", money_source: nil)

    assert_not income.valid?
    assert_includes income.errors[:money_source], I18n.t("activerecord.errors.messages.money_source_required")
  end

  test "an expense and an income with a money source validate" do
    expense = @user.expenses.create!(amount: 50_000, description: "Almuerzo", date: Date.current,
                                     kind: "expense", source: "manual", money_source: @source)
    income = @user.transactions.create!(amount: 200_000, description: "Salario", date: Date.current,
                                        kind: "income", source: "manual", money_source: @source)

    assert expense.persisted?
    assert income.persisted?
  end
end
