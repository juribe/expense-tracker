# frozen_string_literal: true

require "test_helper"

class TransferTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Test User", email: "transfer_test@example.com", password: "password123")
    @savings = @user.money_sources.create!(name: "Savings", kind: "account", starting_balance: 1000)
    @checking = @user.money_sources.create!(name: "Checking", kind: "account", starting_balance: 0)
  end

  def create_transfer(**overrides)
    Transfer.create!(
      { user: @user, from_source: @savings, to_source: @checking, amount: 100, date: Date.current }.merge(overrides)
    )
  end

  test "is valid with required attributes" do
    transfer = Transfer.new(user: @user, from_source: @savings, to_source: @checking, amount: 50, date: Date.current)
    assert transfer.valid?
  end

  test "amount must be present and greater than 0" do
    transfer = Transfer.new(user: @user, from_source: @savings, to_source: @checking, date: Date.current)
    assert_not transfer.valid?
    assert_includes transfer.errors[:amount], I18n.t("errors.messages.blank")

    transfer.amount = 0
    assert_not transfer.valid?
    assert_includes transfer.errors[:amount], I18n.t("errors.messages.greater_than", count: 0)

    transfer.amount = -10
    assert_not transfer.valid?
    assert_includes transfer.errors[:amount], I18n.t("errors.messages.greater_than", count: 0)
  end

  test "date must be present" do
    transfer = Transfer.new(user: @user, from_source: @savings, to_source: @checking, amount: 100)
    assert_not transfer.valid?
    assert_includes transfer.errors[:date], I18n.t("errors.messages.blank")
  end

  test "from_source and to_source must be different" do
    transfer = Transfer.new(user: @user, from_source: @savings, to_source: @savings, amount: 100, date: Date.current)
    assert_not transfer.valid?
    assert_includes transfer.errors[:to_source], I18n.t("validation.transfer_sources")
  end

  test "for_user scope filters by user" do
    other_user = User.create!(name: "Other", email: "other_transfer_test@example.com", password: "password123")
    other_source_a = other_user.money_sources.create!(name: "A", kind: "account", starting_balance: 100)
    other_source_b = other_user.money_sources.create!(name: "B", kind: "account")
    my_transfer = create_transfer
    other_transfer = Transfer.create!(user: other_user, from_source: other_source_a, to_source: other_source_b, amount: 50, date: Date.current)
    assert_includes Transfer.for_user(@user), my_transfer
    assert_not_includes Transfer.for_user(@user), other_transfer
  end

  test "recent scope orders by date descending" do
    old = create_transfer(date: Date.new(2026, 1, 1), amount: 10)
    new_t = create_transfer(date: Date.new(2026, 6, 1), amount: 20)
    results = Transfer.recent(2)
    assert_equal new_t.id, results.first.id
    assert_equal old.id, results.last.id
  end

  test "destroying transfer does not affect sources" do
    transfer = create_transfer
    assert_difference "MoneySource.count", 0 do
      transfer.destroy
    end
  end

  # ----- Pockets -----

  test "assigning money to a pocket moves the balance without touching expense totals" do
    @pocket = @user.money_sources.create!(name: "Bolsillo Europa", kind: "pocket", starting_balance: 0)
    @savings.update!(starting_balance: 2_000_000)

    Transfer.create!(user: @user, from_source: @savings, to_source: @pocket, amount: 1_000_000, date: Date.current)

    # 2_000_000 starting balance minus the assigned amount
    assert_equal 1_000_000, @savings.reload.balance.to_i
    assert_equal 1_000_000, @pocket.reload.balance.to_i
    assert_equal 0, Expense.count
    assert_equal 0, Income.count
  end

  test "moving money out of a pocket is a transfer, not an income" do
    @pocket = @user.money_sources.create!(name: "Bolsillo Europa", kind: "pocket", starting_balance: 1_000_000)

    Transfer.create!(user: @user, from_source: @pocket, to_source: @savings, amount: 400_000, date: Date.current)

    assert_equal 600_000, @pocket.reload.balance.to_i
    assert_equal 401_000, @savings.reload.balance.to_i
    assert_equal 0, Income.count
  end

  test "money can be re-assigned between pockets" do
    @pocket_a = @user.money_sources.create!(name: "Bolsillo A", kind: "pocket", starting_balance: 500_000)
    @pocket_b = @user.money_sources.create!(name: "Bolsillo B", kind: "pocket", starting_balance: 0)

    Transfer.create!(user: @user, from_source: @pocket_a, to_source: @pocket_b, amount: 200_000, date: Date.current)

    assert_equal 300_000, @pocket_a.reload.balance.to_i
    assert_equal 200_000, @pocket_b.reload.balance.to_i
  end

  test "a pocket cannot fund a debt payment" do
    @pocket = @user.money_sources.create!(name: "Bolsillo", kind: "pocket", starting_balance: 500_000)
    card = @user.money_sources.create!(name: "Tarjeta", kind: "credit_card", starting_balance: 0)

    transfer = Transfer.new(user: @user, from_source: @pocket, to_source: card, amount: 100, date: Date.current)
    assert_not transfer.valid?
    assert_includes transfer.errors[:to_source], I18n.t("activerecord.errors.messages.pocket_flow")
  end

  test "a debt cannot transfer into a pocket" do
    @pocket = @user.money_sources.create!(name: "Bolsillo", kind: "pocket", starting_balance: 0)
    loan = @user.money_sources.create!(name: "Préstamo", kind: "loan", starting_balance: 0)

    transfer = Transfer.new(user: @user, from_source: loan, to_source: @pocket, amount: 100, date: Date.current)
    assert_not transfer.valid?
    assert_includes transfer.errors[:to_source], I18n.t("activerecord.errors.messages.pocket_flow")
  end

  test "releasing pocket money with no allocations is free" do
    @pocket = @user.money_sources.create!(name: "Bolsillo", kind: "pocket", starting_balance: 1_000_000)
    goal = Goal.create!(user: @user, pocket: @pocket, name: "Viaje", target_amount: 5_000_000)

    transfer = Transfer.new(user: @user, from_source: @pocket, to_source: @savings, amount: 1_000_000, date: Date.current)
    assert transfer.valid?
  end

  test "releasing more than the unallocated balance is blocked" do
    @pocket = @user.money_sources.create!(name: "Bolsillo", kind: "pocket", starting_balance: 1_000_000)
    goal = Goal.create!(user: @user, pocket: @pocket, name: "Viaje", target_amount: 5_000_000)
    goal.goal_allocations.create!(pocket: @pocket, amount: 800_000, date: Date.current)

    transfer = Transfer.new(user: @user, from_source: @pocket, to_source: @savings, amount: 500_000, date: Date.current)
    assert_not transfer.valid?
    assert_includes transfer.errors[:amount], I18n.t("activerecord.errors.messages.pocket_allocations_exceed_balance")
  end

  test "releasing only the unallocated balance leaves allocations covered" do
    @pocket = @user.money_sources.create!(name: "Bolsillo", kind: "pocket", starting_balance: 1_000_000)
    goal = Goal.create!(user: @user, pocket: @pocket, name: "Viaje", target_amount: 5_000_000)
    goal.goal_allocations.create!(pocket: @pocket, amount: 800_000, date: Date.current)

    Transfer.create!(user: @user, from_source: @pocket, to_source: @savings, amount: 200_000, date: Date.current)

    assert_equal 800_000, @pocket.reload.balance.to_i
    assert_equal 0, @pocket.reload.unallocated_amount.to_i
    assert_equal 800_000, goal.reload.saved_amount
    assert_equal 0, Expense.count
    assert_equal 0, Income.count
  end

  # ----- Debt targets -----

  test "a transfer into a revolving loan lowers the outstanding balance; destroy restores it" do
    loan = @user.money_sources.create!(name: "Crédito Rotativo", kind: "loan", sub_kind: "revolving", starting_balance: 0)
    loan.create_credit_account!(outstanding_balance: 8_000_000)
    loan.reload

    transfer = create_transfer(to_source: loan, amount: 2_000_000)

    assert_equal BigDecimal("6_000_000"), loan.reload.credit_account.outstanding_balance.to_d

    transfer.destroy

    assert_equal BigDecimal("8_000_000"), loan.reload.credit_account.outstanding_balance.to_d
  end

  test "a transfer into a credit card lowers the card's used credit and frees the limit" do
    card = @user.money_sources.create!(name: "Tarjeta", kind: "credit_card", starting_balance: -8_000_000)
    card.create_credit_account!(credit_limit: 10_000_000)
    card.reload

    transfer = create_transfer(to_source: card, amount: 2_000_000)

    assert_equal BigDecimal("6_000_000"), card.reload.used_credit
    assert_equal BigDecimal("4_000_000"), card.available_credit
    assert_equal 0, Expense.count

    transfer.destroy

    assert_equal BigDecimal("8_000_000"), card.reload.used_credit
  end

  test "a transfer out of a revolving loan raises the outstanding balance; destroy restores it" do
    loan = @user.money_sources.create!(name: "Crédito Rotativo", kind: "loan", sub_kind: "revolving", starting_balance: 0)
    loan.create_credit_account!(outstanding_balance: 8_000_000)
    loan.reload

    transfer = create_transfer(from_source: loan, to_source: @checking, amount: 2_000_000)

    assert_equal BigDecimal("10_000_000"), loan.reload.credit_account.outstanding_balance.to_d

    transfer.destroy

    assert_equal BigDecimal("8_000_000"), loan.reload.credit_account.outstanding_balance.to_d
  end

  test "a transfer out of a credit card raises the card's used credit (advance)" do
    card = @user.money_sources.create!(name: "Tarjeta", kind: "credit_card", starting_balance: -1_000_000)
    card.create_credit_account!(credit_limit: 10_000_000)
    card.reload

    transfer = create_transfer(from_source: card, to_source: @checking, amount: 300_000)

    assert_equal BigDecimal("1_300_000"), card.reload.used_credit

    transfer.destroy

    assert_equal BigDecimal("1_000_000"), card.reload.used_credit
  end

  test "a transfer out of a non-revolving loan never touches the outstanding balance" do
    loan = @user.money_sources.create!(name: "Hipotecario", kind: "loan", sub_kind: "mortgage", starting_balance: 0)
    loan.create_credit_account!(outstanding_balance: 30_000_000)
    loan.reload

    create_transfer(from_source: loan, to_source: @checking, amount: 2_000_000)

    assert_equal BigDecimal("30_000_000"), loan.reload.credit_account.outstanding_balance.to_d
  end

  test "asset transfers never touch outstanding balances" do
    loan = @user.money_sources.create!(name: "Hipotecario", kind: "loan", sub_kind: "mortgage", starting_balance: 0)
    loan.create_credit_account!(outstanding_balance: 30_000_000)
    @savings.update!(starting_balance: 1000)

    create_transfer(amount: 400)

    assert_equal BigDecimal("30_000_000"), loan.reload.credit_account.outstanding_balance.to_d
    assert_equal BigDecimal("600"), @savings.reload.balance.to_i
    assert_equal BigDecimal("400"), @checking.reload.balance.to_i
  end

  # ----- Ownership -----

  test "is invalid when the origin source belongs to another user" do
    other_user = User.create!(name: "Other", email: "transfer_origin_owner@example.com", password: "password123")
    foreign = other_user.money_sources.create!(name: "Ajena", kind: "account", starting_balance: 1000)
    balance_before = foreign.reload.cached_balance

    transfer = Transfer.new(user: @user, from_source: foreign, to_source: @checking, amount: 100, date: Date.current)

    assert_not transfer.valid?
    assert_includes transfer.errors[:from_source], I18n.t("activerecord.errors.messages.other_user")
    assert_equal balance_before, foreign.reload.cached_balance
  end

  test "is invalid when the destination source belongs to another user" do
    other_user = User.create!(name: "Other", email: "transfer_destination_owner@example.com", password: "password123")
    foreign = other_user.money_sources.create!(name: "Ajena", kind: "account", starting_balance: 0)

    transfer = Transfer.new(user: @user, from_source: @savings, to_source: foreign, amount: 100, date: Date.current)

    assert_not transfer.valid?
    assert_includes transfer.errors[:to_source], I18n.t("activerecord.errors.messages.other_user")
  end

  test "an invalid cross-user transfer leaves every cached balance untouched" do
    other_user = User.create!(name: "Other", email: "transfer_balance_owner@example.com", password: "password123")
    foreign = other_user.money_sources.create!(name: "Ajena", kind: "account", starting_balance: 500)
    savings_before = @savings.reload.cached_balance
    checking_before = @checking.reload.cached_balance
    foreign_before = foreign.reload.cached_balance

    transfer = Transfer.new(user: @user, from_source: foreign, to_source: @checking, amount: 100, date: Date.current)

    assert_not transfer.save
    assert_equal savings_before, @savings.reload.cached_balance
    assert_equal checking_before, @checking.reload.cached_balance
    assert_equal foreign_before, foreign.reload.cached_balance
  end
end
