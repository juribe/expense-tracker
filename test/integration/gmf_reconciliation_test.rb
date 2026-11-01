# frozen_string_literal: true

require "test_helper"

class GmfReconciliationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @user = User.create!(name: "Rec User", email: "rec_#{SecureRandom.hex(4)}@example.com", password: "password123")
    @account = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 100_000_000, gmf_exempt: false)
    @category = Category.find_or_create_by!(name: "GmfTestFood", category_type: "expense")
    GmfUvtYear.find_or_create_by!(year: 2026) { |r| r.value = 52374.00 }
  end

  teardown do
    GmfMonthlyAccumulator.where(user_id: @user.id).delete_all if @user
    Payment.where(user_id: @user.id).delete_all if @user
    Expense.where(user_id: @user.id).delete_all if @user
    Expense.where(category_id: Category.where(name: ["Impuestos y gravámenes", "4x1.000 (GMF)", "GmfTestFood"]).select(:id)).delete_all
    Transfer.where(user_id: @user.id).delete_all if @user
    @user.money_sources.delete_all if @user&.persisted?
    @user.destroy if @user&.persisted?
    Category.where(name: ["Impuestos y gravámenes", "4x1.000 (GMF)", "GmfTestFood"]).delete_all
    GmfUvtYear.delete_all
    self.use_transactional_tests = true
  end

  test "estimated gmf reconciled when bank charge arrives" do
    expense = @user.expenses.create!(
      category: @category, amount: 100_000, date: Date.new(2026, 11, 10),
      source: "manual", money_source: @account, kind: "expense"
    )
    estimated = Expense.find_by(gmf_origin_type: "Expense", gmf_origin_id: expense.id)
    assert_not_nil estimated
    assert estimated.gmf_estimated?

    # bank sends GMF charge separately
    bank_expense = @user.expenses.create!(
      category: estimated.category, amount: 400, date: Date.new(2026, 11, 10),
      source: "gmail", money_source: @account, kind: "expense",
      description: "GMF 4x1000 cargo bancario"
    )

    estimated.reload
    assert_equal "reconciled", estimated.gmf_status
    assert_not estimated.gmf_estimated?
    assert_nil Expense.find_by(id: bank_expense.id)
  end

  test "bank charge without prior estimate creates charged expense" do
    bank_expense = @user.expenses.create!(
      category: @category, amount: 400, date: Date.new(2026, 11, 10),
      source: "gmail", money_source: @account, kind: "expense",
      description: "Cargo 4x1000"
    )
    bank_expense.reload
    assert_equal "charged", bank_expense.gmf_status
    assert_equal "gmf", bank_expense.source
  end
end
