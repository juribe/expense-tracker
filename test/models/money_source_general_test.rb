# frozen_string_literal: true

require "test_helper"

class MoneySourceGeneralTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "General Source", email: "general_source_test@example.com", password: "password123")
  end

  test "General is a real payment source in simple mode" do
    @user.update!(money_tracking_mode: "simple", money_tracking_mode_selected_at: Time.current)
    general = MoneySources::General.ensure_for(@user)

    assert_equal "general", general.kind
    assert general.general?
    assert general.payment_source?
    refute general.balance_guarded?
    assert_equal "General", general.name
    assert_nil general.identifier
    assert_nil general.bank
  end

  test "General accepts expenses and incomes" do
    @user.update!(money_tracking_mode: "simple", money_tracking_mode_selected_at: Time.current)
    general = MoneySources::General.ensure_for(@user)
    category = Category.create!(name: "General Moves", is_default: true, category_type: "expense")

    expense = @user.expenses.create!(amount: 10_000, date: Date.current, description: "Gasto",
                                     category: category, money_source: general)
    income = @user.incomes.create!(amount: 25_000, date: Date.current, description: "Ingreso",
                                   money_source: general)

    assert equal_model?(general, expense.money_source)
    assert equal_model?(general, income.money_source)
    assert_equal BigDecimal("15000"), general.reload.balance
  end

  test "General is created as an account for an advanced user" do
    general = MoneySources::General.ensure_for(@user)

    assert_equal "account", general.kind
    assert general.general?
    assert general.payment_source?
  end

  test "soft deleting General hides it but keeps its movements and frees the slot" do
    general = MoneySources::General.ensure_for(@user)
    category = Category.create!(name: "General archivada", is_default: true, category_type: "expense")
    expense = @user.expenses.create!(amount: 10_000, date: Date.current, description: "Gasto archivado",
                                     category: category, source: "ai", money_source: general)

    general.soft_delete!

    archived = MoneySource.with_deleted.find(general.id)
    assert archived.soft_deleted?
    refute archived.active?
    assert archived.general?
    refute_includes @user.money_sources.reload.map(&:id), general.id
    assert_equal general.id, expense.reload.money_source_id
    assert_equal general.id, expense.money_source.id
    assert Expense.exists?(expense.id)

    restored = MoneySources::General.ensure_for_simple(@user)
    assert_equal general.id, restored.id
    refute restored.soft_deleted?
    assert restored.general?
  end

  test "an archived General does not block creating a new active one" do
    archived = MoneySources::General.ensure_for(@user)
    archived.soft_delete!

    fresh = MoneySources::General.ensure_for(@user)

    refute_equal archived.id, fresh.id
    assert fresh.general?
    assert fresh.persisted?
  end

  test "only one General source may exist per user" do
    first = MoneySources::General.ensure_for(@user)

    duplicate = @user.money_sources.build(name: "Otra General", kind: "account", general: true)

    refute duplicate.valid?
    assert duplicate.errors[:general].any?
    assert first.persisted?
  end

  test "a converted account can return to General when it has no dependent structures" do
    @user.update!(money_tracking_mode: "simple", money_tracking_mode_selected_at: Time.current)
    general = MoneySources::General.ensure_for(@user)
    general.update!(kind: "account")

    assert general.convertible_to_general?
  end

  test "an account with dependent accounts is not converted back to General" do
    @user.update!(money_tracking_mode: "simple", money_tracking_mode_selected_at: Time.current)
    general = MoneySources::General.ensure_for(@user)
    general.update!(kind: "account")
    @user.money_sources.create!(name: "Débito", kind: "debit_card", parent: general)

    refute general.reload.convertible_to_general?
  end

  private

  def equal_model?(expected, actual)
    expected.id == actual.id
  end
end
