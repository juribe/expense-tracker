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

  test "deleting gmf charge recalculates the month with the current exemption" do
    expense = create_expense(amount: 29_000)
    assert_equal 29_000.to_d, accumulator.total_debits
    assert_equal 116.to_d, accumulator.gmf_generated

    @account.update!(gmf_exempt: true)
    charge = Expense.find_by(gmf_origin_type: "Expense", gmf_origin_id: expense.id)
    charge.destroy!

    assert Expense.exists?(expense.id)
    accumulator.reload
    assert_equal 29_000.to_d, accumulator.total_debits
    assert_equal 29_000.to_d, accumulator.covered_by_exemption
    assert_equal 0.to_d, accumulator.taxable
    assert_equal 0.to_d, accumulator.gmf_generated
  end

  test "deleting origin after marking the account exempt clears the accumulator" do
    expense = create_expense(amount: 29_000)
    @account.update!(gmf_exempt: true)

    expense.destroy!

    accumulator.reload
    assert_equal 0.to_d, accumulator.total_debits
    assert_equal 0.to_d, accumulator.covered_by_exemption
    assert_equal 0.to_d, accumulator.taxable
    assert_equal 0.to_d, accumulator.gmf_generated
    assert_nil Expense.find_by(gmf_origin_type: "Expense", gmf_origin_id: expense.id)
  end

  test "editing origin after marking the account exempt recalculates the month" do
    expense = create_expense(amount: 29_000)
    @account.update!(gmf_exempt: true)

    expense.update!(amount: 58_000)

    accumulator.reload
    assert_equal 58_000.to_d, accumulator.total_debits
    assert_equal 58_000.to_d, accumulator.covered_by_exemption
    assert_equal 0.to_d, accumulator.taxable
    assert_equal 0.to_d, accumulator.gmf_generated
    assert_nil Expense.find_by(gmf_origin_type: "Expense", gmf_origin_id: expense.id)
  end

  test "deleting transfer after marking the account exempt clears the accumulator" do
    destination = @user.money_sources.create!(name: "Destino", kind: "account", starting_balance: 0)
    transfer = Transfer.create!(
      user: @user, from_source: @account, to_source: destination,
      amount: 29_000, date: Date.new(2026, 11, 10)
    )
    assert_equal 29_000.to_d, accumulator.total_debits
    @account.update!(gmf_exempt: true)

    transfer.destroy!

    accumulator.reload
    assert_equal 0.to_d, accumulator.total_debits
    assert_equal 0.to_d, accumulator.covered_by_exemption
    assert_equal 0.to_d, accumulator.taxable
    assert_equal 0.to_d, accumulator.gmf_generated
  end

  test "recalculating a month does not query each movement money source" do
    3.times { create_expense(amount: 10_000) }
    destination = @user.money_sources.create!(name: "Destino", kind: "account", starting_balance: 0)
    Transfer.create!(
      user: @user, from_source: @account, to_source: destination,
      amount: 5_000, date: Date.new(2026, 11, 10)
    )

    # The query cache would collapse the repeated belongs-to lookups into one;
    # disabling it exposes the N+1 the way a request with distinct rows does.
    queries = ActiveRecord::Base.uncached do
      money_source_id_queries do
        Gmf::AccumulatorRecalculator.call(user: @user, money_source: @account, date: Date.new(2026, 11, 10))
      end
    end

    assert_operator queries.length, :<=, 2,
      "expected at most two money-source lookups (expenses and transfers), " \
      "got #{queries.length}: #{queries.join(' | ')}"
  end

  private

  # Belongs-to lookups issued per record when an association is not
  # preloaded. Eager loading uses the same WHERE "money_sources"."id" form
  # but only once, so it must not scale with the number of movements.
  def money_source_id_queries
    queries = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:name] == "SCHEMA" || payload[:cached]

      sql = payload[:sql].to_s
      queries << sql if sql.match?(/WHERE "money_sources"\."id"/i)
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries
  end

  def create_expense(amount:, date: Date.new(2026, 11, 10))
    @user.expenses.create!(
      category: @category, amount:, date:,
      source: "manual", money_source: @account, kind: "expense"
    )
  end

  def accumulator
    GmfMonthlyAccumulator.find_by(
      user_id: @user.id, money_source_id: @account.id,
      year: 2026, month: 11
    )
  end
end
