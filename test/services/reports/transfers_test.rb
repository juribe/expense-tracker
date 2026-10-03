# frozen_string_literal: true

require "test_helper"

class ReportsTransfersTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Transfer User", email: "reports_transfers_test@example.com", password: "password123")
    @bank = @user.money_sources.create!(name: "Davibank", kind: "account", active: true)
    @savings = @user.money_sources.create!(name: "Ahorros", kind: "account", active: true)
    @card = @user.money_sources.create!(name: "Visa", kind: "credit_card", active: true)
    @loan = @user.money_sources.create!(name: "Rotativo", kind: "loan", active: true)
    @other = User.create!(name: "Other", email: "reports_transfers_other@example.com", password: "password123")
    @other_bank = @other.money_sources.create!(name: "Other Bank", kind: "account", active: true)
    @period = Reports::Period.new(preset: "this_month", date: Date.new(2026, 9, 15))
    @filter = Reports::Filter.new(user: @user, period: @period)
  end

  def transfer(from:, to:, amount:, date: Date.new(2026, 9, 10), user: @user)
    Transfer.create!(user: user, from_source: from, to_source: to, amount: amount, date: date)
  end

  def report
    Reports::Transfers.new(user: @user, filter: @filter).call
  end

  test "groups transfers by source destination route" do
    transfer(from: @bank, to: @savings, amount: 1_000_000)
    transfer(from: @loan, to: @bank, amount: 3_000_000)
    transfer(from: @bank, to: @card, amount: 2_000_000)
    transfer(from: @other_bank, to: @card, amount: 7_000_000, user: @other)

    data = report

    assert_equal 6_000_000.to_d, data[:total]
    assert_equal 3, data[:count]
    assert_equal 3, data[:routes].size
  end

  test "route rows carry names, amount, count and date range" do
    transfer(from: @bank, to: @savings, amount: 400_000, date: Date.new(2026, 9, 2))
    transfer(from: @bank, to: @savings, amount: 600_000, date: Date.new(2026, 9, 18))

    route = report[:routes].first

    assert_equal "Davibank", route[:from_name]
    assert_equal "Ahorros", route[:to_name]
    assert_equal 1_000_000.to_d, route[:total]
    assert_equal 2, route[:count]
    assert_equal Date.new(2026, 9, 2), route[:first_date]
    assert_equal Date.new(2026, 9, 18), route[:last_date]
  end

  test "transfers into a debt target are flagged as debt payments" do
    transfer(from: @bank, to: @card, amount: 2_000_000)

    assert_equal :debt_payment, report[:routes].first[:movement]
  end

  test "transfers out of a loan are flagged as disbursements" do
    transfer(from: @loan, to: @bank, amount: 3_000_000)

    assert_equal :disbursement, report[:routes].first[:movement]
  end

  test "plain account transfers are flagged as internal" do
    transfer(from: @bank, to: @savings, amount: 1_000_000)

    assert_equal :internal, report[:routes].first[:movement]
  end

  test "routes are sorted from highest to lowest total" do
    transfer(from: @bank, to: @savings, amount: 1_000_000)
    transfer(from: @loan, to: @bank, amount: 3_000_000)

    assert_equal 3_000_000.to_d, report[:routes].first[:total]
  end

  test "respects the money source filter on either end" do
    transfer(from: @bank, to: @savings, amount: 1_000_000)
    transfer(from: @loan, to: @bank, amount: 3_000_000)
    transfer(from: @bank, to: @card, amount: 2_000_000)
    scoped_filter = Reports::Filter.new(user: @user, period: @period, money_source_id: @bank.id)

    data = Reports::Transfers.new(user: @user, filter: scoped_filter).call

    assert_equal 3, data[:count]
    assert_equal 6_000_000.to_d, data[:total]
  end

  test "empty period yields zeroed structure" do
    data = report

    assert_empty data[:routes]
    assert_equal 0.to_d, data[:total]
    assert_equal 0, data[:count]
  end
end
