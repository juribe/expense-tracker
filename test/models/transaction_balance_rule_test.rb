# frozen_string_literal: true

require "test_helper"

class TransactionBalanceRuleTest < ActiveSupport::TestCase
  setup do
    @category = Category.create!(name: "Balance Rule Expense", is_default: true, category_type: "expense")
    @income_category = Category.create!(name: "Balance Rule Income", is_default: true, category_type: "income")
  end

  test "simple mode allows a manual expense above the General balance" do
    user = simple_user
    general = user.general_money_source

    expense = user.expenses.create!(amount: 30_000, date: Date.current, description: "Almuerzo",
                                    category: @category, source: "manual", money_source: general)

    assert expense.persisted?
    assert_equal general.id, expense.money_source_id
    assert_equal BigDecimal("-30000"), general.reload.balance
  end

  test "simple mode allows the source to be omitted entirely" do
    user = simple_user
    general = user.general_money_source

    expense = user.expenses.create!(amount: 30_000, date: Date.current, description: "Almuerzo",
                                    category: @category, source: "manual")

    assert_equal general.id, expense.reload.money_source_id
    assert_equal BigDecimal("-30000"), general.reload.balance
  end

  test "simple mode uses General for automatic channels and never blocks them by balance" do
    user = simple_user
    general = user.general_money_source

    gmail_expense = Expenses::Create.call(
      user: user,
      amount: 40_000,
      description: "Correo",
      category: @category,
      occurred_at: Date.current,
      source: :gmail
    )
    whatsapp_expense = Expenses::Create.call(
      user: user,
      amount: 20_000,
      description: "WhatsApp",
      category: @category,
      occurred_at: Date.current,
      source: :whatsapp
    )

    assert_equal general.id, gmail_expense.money_source_id
    assert_equal general.id, whatsapp_expense.money_source_id
    assert_equal BigDecimal("-60000"), general.reload.balance
  end

  test "an income recovers the negative General balance without adjustments" do
    user = simple_user
    general = user.general_money_source
    user.expenses.create!(amount: 30_000, date: Date.current, description: "Almuerzo",
                          category: @category, source: "manual")
    assert_equal BigDecimal("-30000"), general.reload.balance

    user.incomes.create!(amount: 50_000, date: Date.current, description: "Ingreso",
                         category: @income_category, source: "manual")

    assert_equal BigDecimal("20000"), general.reload.balance
    assert_equal 0, user.balance_adjustments.count
    assert_equal 0, user.reconciliation_snapshots.count
  end

  test "advanced mode keeps blocking a manual expense above the account balance" do
    user = detailed_user
    account = user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 10_000)

    expense = user.expenses.build(amount: 30_000, date: Date.current, description: "Almuerzo",
                                  category: @category, source: "manual", money_source: account)

    refute expense.valid?
    assert expense.errors[:money_source].any?
    assert_equal BigDecimal("10000"), account.reload.balance
  end

  test "advanced credit cards keep their specific debt behavior" do
    user = detailed_user
    card = user.money_sources.create!(name: "Visa", kind: "credit_card", starting_balance: 0)

    expense = user.expenses.create!(amount: 100_000, date: Date.current, description: "Compra",
                                    category: @category, source: "manual", money_source: card)

    assert expense.persisted?
    assert_equal BigDecimal("-100000"), card.reload.balance
  end

  test "non-balance integrity validations still apply in simple mode" do
    user = simple_user

    expense = user.expenses.build(amount: 0, date: nil, description: "Inválido",
                                  category: @category, source: "manual")

    refute expense.valid?
    assert expense.errors[:amount].any?
    assert expense.errors[:date].any?
  end

  private

  def simple_user
    user = User.create!(name: "Simple Balance", email: "simple_balance_#{SecureRandom.hex(4)}@example.com",
                        password: "password123")
    user.update!(money_tracking_mode: "simple", money_tracking_mode_selected_at: Time.current)
    user.ensure_general_money_source!
    user
  end

  def detailed_user
    User.create!(name: "Advanced Balance", email: "advanced_balance_#{SecureRandom.hex(4)}@example.com",
                 password: "password123")
  end
end
