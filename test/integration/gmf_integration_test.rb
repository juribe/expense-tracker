# frozen_string_literal: true

require "test_helper"

class GmfIntegrationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @user = User.create!(name: "Int User", email: "int_#{SecureRandom.hex(4)}@example.com", password: "password123")
    @account = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 100_000_000, gmf_exempt: true)
    @category = Category.find_or_create_by!(name: "Food", category_type: "expense")
    GmfUvtYear.find_or_create_by!(year: 2026) { |r| r.value = 52374.00 }
  end

  teardown do
    GmfUvtYear.delete_all
    GmfMonthlyAccumulator.where(user_id: @user.id).delete_all if @user
    Expense.where(user_id: @user.id).delete_all if @user
    Category.where(name: ["Impuestos y gravámenes", "4x1.000 (GMF)"]).delete_all
    Transfer.where(user_id: @user.id).delete_all if @user
    @user.money_sources.delete_all if @user&.persisted?
    @user.destroy if @user&.persisted?
    self.use_transactional_tests = true
  end

  test "expense on non-exempt account creates gmf charge" do
    other = @user.money_sources.create!(name: "Otra", kind: "account", starting_balance: 100_000_000)
    expense = @user.expenses.create!(
      category: @category, amount: 100_000, date: Date.new(2026, 11, 10),
      source: "manual", money_source: other, kind: "expense"
    )
    gmf = Expense.where(user: @user, gmf_origin_type: "Expense", gmf_origin_id: expense.id).first
    assert_not_nil gmf
    assert_equal (100_000 * 0.004).to_d, gmf.amount.abs
  end

  test "credit card purchase does not create gmf" do
    card = @user.money_sources.create!(name: "Card", kind: "credit_card", starting_balance: 0)
    expense = @user.expenses.create!(
      category: @category, amount: 100_000, date: Date.new(2026, 11, 10),
      source: "manual", money_source: card, kind: "expense"
    )
    gmf = Expense.where(user: @user, gmf_origin_type: "Expense", gmf_origin_id: expense.id).first
    assert_nil gmf
  end

  test "transfer from non-exempt account creates gmf charge" do
    other = @user.money_sources.create!(name: "Otra", kind: "account", starting_balance: 100_000_000)
    dest = @user.money_sources.create!(name: "Dest", kind: "account", starting_balance: 0)
    transfer = Transfer.create!(
      user: @user, from_source: other, to_source: dest, amount: 100_000,
      date: Date.new(2026, 11, 10)
    )
    gmf = Expense.where(user: @user, gmf_origin_type: "Transfer", gmf_origin_id: transfer.id).first
    assert_not_nil gmf
  end
end
