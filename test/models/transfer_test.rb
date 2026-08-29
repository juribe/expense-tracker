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
      { user: @user, from_source: @savings, to_source: @checking, amount: 100, date: Date.today }.merge(overrides)
    )
  end

  test "is valid with required attributes" do
    transfer = Transfer.new(user: @user, from_source: @savings, to_source: @checking, amount: 50, date: Date.today)
    assert transfer.valid?
  end

  test "amount must be present and greater than 0" do
    transfer = Transfer.new(user: @user, from_source: @savings, to_source: @checking, date: Date.today)
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
    transfer = Transfer.new(user: @user, from_source: @savings, to_source: @savings, amount: 100, date: Date.today)
    assert_not transfer.valid?
    assert_includes transfer.errors[:to_source], I18n.t("validation.transfer_sources")
  end

  test "for_user scope filters by user" do
    other_user = User.create!(name: "Other", email: "other_transfer_test@example.com", password: "password123")
    other_source_a = other_user.money_sources.create!(name: "A", kind: "account")
    other_source_b = other_user.money_sources.create!(name: "B", kind: "account")
    my_transfer = create_transfer
    other_transfer = Transfer.create!(user: other_user, from_source: other_source_a, to_source: other_source_b, amount: 50, date: Date.today)
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
end
