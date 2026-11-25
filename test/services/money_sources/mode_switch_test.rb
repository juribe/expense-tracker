# frozen_string_literal: true

require "test_helper"

module MoneySources
  class ModeSwitchTest < ActiveSupport::TestCase
    setup do
      @category = Category.create!(name: "Mode Switch Category", is_default: true, category_type: "expense")
      @income_category = Category.create!(name: "Mode Switch Income", is_default: true, category_type: "income")
    end

    test "switching to advanced converts General into an account preserving its id and movements" do
      user = simple_user_with_movements
      general = user.general_money_source
      expense = user.expenses.order(:created_at).first
      income = user.incomes.order(:created_at).first
      balance_before = general.balance
      expense_before = expense.attributes.slice("id", "money_source_id", "amount", "date", "category_id")
      income_before = income.attributes.slice("id", "money_source_id", "amount", "date", "category_id")

      result = ModeSwitch.new(user: user, mode: "detailed").call

      assert result.success?
      user.reload
      assert_equal "detailed", user.money_tracking_mode
      assert user.money_tracking_mode_selected?
      assert_equal general.id, user.general_money_source.id
      assert_equal "account", general.reload.kind
      assert_equal general.id, user.default_money_source_id
      assert_equal balance_before, general.balance
      assert_equal expense_before, expense.reload.attributes.slice("id", "money_source_id", "amount", "date", "category_id")
      assert_equal income_before, income.reload.attributes.slice("id", "money_source_id", "amount", "date", "category_id")
    end

    test "switching to advanced twice is idempotent" do
      user = simple_user_with_movements
      first = ModeSwitch.new(user: user, mode: "detailed").call
      general_id = user.reload.general_money_source.id

      assert first.success?
      assert_no_difference "MoneySource.count" do
        second = ModeSwitch.new(user: user, mode: "detailed").call
        assert second.success?
      end
      assert_equal general_id, user.reload.general_money_source.id
      assert_equal "account", user.general_money_source.kind
    end

    test "switching an advanced user to advanced does not create a General source" do
      user = User.create!(name: "Advanced Only", email: "advanced_only_#{SecureRandom.hex(4)}@example.com",
                          password: "password123")
      user.money_sources.create!(name: "Cuenta propia", kind: "account")

      assert_no_difference "MoneySource.count" do
        assert ModeSwitch.new(user: user, mode: "detailed").call.success?
      end

      refute user.reload.money_sources.exists?(general: true)
      assert_nil user.default_money_source_id
    end

    test "switching back to simple reuses the archived General" do
      user = User.create!(name: "Archived General", email: "archived_general_#{SecureRandom.hex(4)}@example.com",
                          password: "password123")
      general = MoneySources::General.ensure_for(user)
      expense = user.expenses.create!(amount: 15_000, date: Date.current, description: "Gasto archivado",
                                      category: @category, source: "ai", money_source: general)
      general.soft_delete!

      result = ModeSwitch.new(user: user, mode: "simple").call

      assert result.success?
      restored = user.reload.general_money_source
      assert_equal general.id, restored.id
      refute restored.soft_deleted?
      assert_equal "general", restored.kind
      assert Expense.exists?(expense.id)
    end

    test "switching back to simple keeps sources and movements and uses General again" do
      user = simple_user_with_movements
      other = user.money_sources.create!(name: "Cuenta aparte", kind: "account")
      ModeSwitch.new(user: user, mode: "detailed").call
      general = user.reload.general_money_source
      expense = user.expenses.order(:created_at).first

      result = ModeSwitch.new(user: user, mode: "simple").call

      assert result.success?
      user.reload
      assert_equal "simple", user.money_tracking_mode
      assert_equal "general", general.reload.kind
      assert_nil user.default_money_source_id
      assert MoneySource.exists?(other.id)
      assert_equal general.id, expense.reload.money_source_id

      new_expense = user.expenses.create!(amount: 5_000, date: Date.current, description: "Nuevo",
                                          category: @category, source: "manual")
      assert_equal general.id, new_expense.reload.money_source_id
    end

    test "switching back to simple twice is idempotent" do
      user = simple_user_with_movements
      ModeSwitch.new(user: user, mode: "detailed").call
      ModeSwitch.new(user: user, mode: "simple").call
      general_id = user.reload.general_money_source.id

      assert_no_difference "MoneySource.count" do
        assert ModeSwitch.new(user: user, mode: "simple").call.success?
      end
      assert_equal general_id, user.reload.general_money_source.id
      assert_equal "general", user.general_money_source.kind
    end

    test "an account with dependent structures is preserved and a new General is created" do
      user = simple_user_with_movements
      ModeSwitch.new(user: user, mode: "detailed").call
      previous_general = user.reload.general_money_source
      child = user.money_sources.create!(name: "Débito", kind: "debit_card", parent: previous_general)
      expense = user.expenses.order(:created_at).first

      assert_difference "MoneySource.count", 1 do
        assert ModeSwitch.new(user: user, mode: "simple").call.success?
      end

      user.reload
      previous_general.reload
      new_general = user.general_money_source
      refute previous_general.general?
      assert_equal "account", previous_general.kind
      assert MoneySource.exists?(child.id)
      assert_equal previous_general.id, expense.reload.money_source_id
      assert_equal "general", new_general.kind
      refute_equal previous_general.id, new_general.id
    end

    test "a failed user update rolls back the source conversion and the mode" do
      user = simple_user_with_movements
      general = user.general_money_source
      user.update_column(:financial_cycle_start_day, 99)

      result = ModeSwitch.new(user: user, mode: "detailed").call

      refute result.success?
      user.reload
      assert_equal "simple", user.money_tracking_mode
      assert_equal "general", general.reload.kind
      assert_nil user.default_money_source_id
    end

    private

    def simple_user_with_movements
      user = User.create!(name: "Mode Switch", email: "mode_switch_#{SecureRandom.hex(4)}@example.com",
                          password: "password123")
      user.update!(money_tracking_mode: "simple", money_tracking_mode_selected_at: Time.current)
      general = user.ensure_general_money_source!
      user.expenses.create!(amount: 20_000, date: Date.current, description: "Gasto",
                            category: @category, money_source: general)
      user.incomes.create!(amount: 50_000, date: Date.current, description: "Ingreso",
                           category: @income_category, money_source: general)
      user
    end
  end
end
