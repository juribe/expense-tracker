# frozen_string_literal: true

require "test_helper"

class GmfEditDeleteTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @user = User.create!(name: "ED User", email: "ed_#{SecureRandom.hex(4)}@example.com", password: "password123")
    @account = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 100_000_000, gmf_exempt: false)
    @category = Category.find_or_create_by!(name: "GmfTestFood", category_type: "expense")
    GmfUvtYear.find_or_create_by!(year: 2026) { |r| r.value = 52374.00 }
  end

  teardown do
    GmfUvtYear.delete_all
    GmfMonthlyAccumulator.where(user_id: @user.id).delete_all if @user
    Expense.where(user_id: @user.id).delete_all if @user
    Category.where(name: ["Impuestos y gravámenes", "4x1.000 (GMF)", "GmfTestFood"]).delete_all
    Transfer.where(user_id: @user.id).delete_all if @user
    @user.money_sources.delete_all if @user&.persisted?
    @user.destroy if @user&.persisted?
    self.use_transactional_tests = true
  end

  test "deleting expense removes gmf charge" do
    expense = @user.expenses.create!(
      category: @category, amount: 100_000, date: Date.new(2026, 11, 10),
      source: "manual", money_source: @account, kind: "expense"
    )
    charge = Expense.find_by(gmf_origin_type: "Expense", gmf_origin_id: expense.id)
    assert_not_nil charge
    expense.destroy
    assert_nil Expense.find_by(id: charge.id)
  end

  test "editing amount updates gmf charge" do
    expense = @user.expenses.create!(
      category: @category, amount: 100_000, date: Date.new(2026, 11, 10),
      source: "manual", money_source: @account, kind: "expense"
    )
    expense.update!(amount: 200_000)
    charge = Expense.find_by(gmf_origin_type: "Expense", gmf_origin_id: expense.id)
    assert_not_nil charge
    assert_equal (200_000 * 0.004).to_d, charge.amount.abs
  end
end
