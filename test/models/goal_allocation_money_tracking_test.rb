# frozen_string_literal: true

require "test_helper"

class GoalAllocationMoneyTrackingTest < ActiveSupport::TestCase
  setup do
    @user = simple_user
    @goal = Goal.create!(user: @user, name: "Vacaciones", target_amount: 5_000_000)
  end

  test "a virtual contribution belongs to the goal without a pocket" do
    allocation = @goal.goal_allocations.create!(amount: 300_000, date: Date.current, note: "Aporte")

    assert allocation.virtual?
    assert_nil allocation.pocket_id
    assert_equal 300_000, @goal.reload.saved_amount
  end

  test "virtual contributions never touch General, expenses, incomes or transfers" do
    general = @user.general_money_source
    balance_before = general.balance
    expense_count = Expense.count
    income_count = Income.count
    transfer_count = Transfer.count

    @goal.goal_allocations.create!(amount: 1_000_000, date: Date.current, note: "Aporte")

    assert_equal balance_before, general.reload.balance
    assert_equal expense_count, Expense.count
    assert_equal income_count, Income.count
    assert_equal transfer_count, Transfer.count
  end

  test "a virtual withdrawal updates the goal balance" do
    @goal.goal_allocations.create!(amount: 500_000, date: Date.current)
    @goal.goal_allocations.create!(amount: -200_000, date: Date.current)

    assert_equal 300_000, @goal.reload.saved_amount
  end

  test "a virtual withdrawal cannot leave the goal negative" do
    @goal.goal_allocations.create!(amount: 100_000, date: Date.current)
    withdrawal = @goal.goal_allocations.build(amount: -200_000, date: Date.current)

    refute withdrawal.valid?
    assert withdrawal.errors[:amount].any?
  end

  test "a virtual allocation cannot carry a pocket" do
    pocket = @user.money_sources.create!(name: "Ahorros", kind: "pocket", starting_balance: 2_000_000)
    allocation = @goal.goal_allocations.build(pocket: pocket, amount: 100_000, date: Date.current)

    refute allocation.valid?
    assert allocation.errors[:pocket].any?
  end

  test "idempotency prevents a duplicated contribution" do
    key = SecureRandom.uuid
    first = @goal.goal_allocations.create!(amount: 100_000, date: Date.current, idempotency_key: key)
    duplicate = @goal.goal_allocations.build(amount: 100_000, date: Date.current, idempotency_key: key)

    refute duplicate.valid?
    assert_equal first.id, @goal.goal_allocations.find_by(idempotency_key: key).id
  end

  private

  def simple_user
    User.create!(name: "Allocation Simple", email: "allocation_simple_#{SecureRandom.hex(4)}@example.com",
                 password: "password123").tap do |user|
      user.update!(money_tracking_mode: "simple", money_tracking_mode_selected_at: Time.current)
    end
  end
end
