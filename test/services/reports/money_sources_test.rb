# frozen_string_literal: true

require "test_helper"

class ReportsMoneySourcesTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Sources User", email: "reports_sources_test@example.com", password: "password123")
    @food = Category.create!(name: "Alimentación", is_default: true, category_type: "expense")
    @bank = @user.money_sources.create!(name: "Davibank", kind: "account", active: true)
    @card = @user.money_sources.create!(name: "Visa", kind: "credit_card", active: true)
    @cash = @user.money_sources.create!(name: "Efectivo", kind: "cash", active: true)
    @loan = @user.money_sources.create!(name: "Rotativo", kind: "loan", active: true)
    @other = User.create!(name: "Other", email: "reports_sources_other@example.com", password: "password123")
    @period = Reports::Period.new(preset: "this_month", date: Date.new(2026, 9, 15))
    @filter = Reports::Filter.new(user: @user, period: @period)
  end

  def expense(amount, source:, date: Date.new(2026, 9, 10), user: @user)
    Expense.create!(user: user, category: @food, money_source: source, amount: amount,
                    date: date, description: "x")
  end

  def report
    Reports::MoneySources.new(user: @user, filter: @filter).call
  end

  test "groups spending by money source kind with shares" do
    expense(-420_000, source: @bank)
    expense(-310_000, source: @card)
    expense(-180_000, source: @cash)
    expense(-90_000, source: @cash, user: @other)

    data = report
    kinds = data[:kinds].index_by { |k| k[:kind] }

    assert_equal 420_000.to_d, kinds["account"][:total]
    assert_in_delta 46.2, kinds["account"][:share_pct], 0.1
    assert_in_delta 34.1, kinds["credit_card"][:share_pct], 0.1
    assert_equal 910_000.to_d, data[:total]
  end

  test "lists sources inside each kind, sorted by spending" do
    expense(-420_000, source: @bank)
    expense(-310_000, source: @card)
    expense(-180_000, source: @cash)

    data = report
    cash = data[:kinds].find { |k| k[:kind] == "cash" }

    assert_equal %w[Efectivo], cash[:sources].map { |s| s[:name] }
    assert_equal 180_000.to_d, cash[:sources].first[:total]
  end

  test "drill-down exposes the underlying transactions" do
    expense(-420_000, source: @bank)
    expense(-310_000, source: @card)

    data = report
    account = data[:kinds].find { |k| k[:kind] == "account" }
    drill = account[:sources].first[:scope].call

    assert_equal 1, drill.count
    assert_equal @bank.id, drill.first.money_source_id
  end

  test "credit card purchases are spending; payments toward the card are not" do
    expense(-310_000, source: @card)
    card_payment = expense(-1_400_000, source: @bank)
    Payment.create!(user: @user, expense: card_payment, money_source: @card, amount: 1_400_000,
                    principal_amount: 1_400_000)

    data = report
    kinds = data[:kinds].index_by { |k| k[:kind] }

    assert_equal 310_000.to_d, kinds["credit_card"][:total]
    assert_nil kinds["account"], "debt payment expense is not spending"
  end

  test "loan installment expenses with payments are not money source spending" do
    installment = expense(-2_800_000, source: @bank)
    Payment.create!(user: @user, expense: installment, money_source: @loan, amount: 2_800_000,
                    principal_amount: 2_800_000)

    assert_equal 0.to_d, report[:total]
  end

  test "transfers are never money source spending" do
    @user.transfers.create!(from_source: @bank, to_source: @card, amount: 1_000_000,
                            date: Date.new(2026, 9, 20))

    assert_equal 0.to_d, report[:total]
  end

  test "respects the money source filter" do
    expense(-420_000, source: @bank)
    expense(-310_000, source: @card)
    scoped_filter = Reports::Filter.new(user: @user, period: @period, credit_card_id: @card.id)

    data = Reports::MoneySources.new(user: @user, filter: scoped_filter).call

    assert_equal 310_000.to_d, data[:total]
    assert_equal 1, data[:kinds].size
  end

  test "respects the category filter" do
    other_food = Category.create!(name: "Otro_#{SecureRandom.hex(4)}", category_type: "expense", user: @user)
    expense(-420_000, source: @bank)
    scoped = Expense.create!(user: @user, category: other_food, money_source: @cash, amount: -100_000,
                             date: Date.new(2026, 9, 10), description: "x")
    scoped_filter = Reports::Filter.new(user: @user, period: @period, category_id: other_food.id)

    data = Reports::MoneySources.new(user: @user, filter: scoped_filter).call

    assert_equal 100_000.to_d, data[:total]
    assert_equal %w[cash], data[:kinds].map { |k| k[:kind] }
  end

  test "kinds are sorted from highest to lowest spending" do
    expense(-420_000, source: @bank)
    expense(-310_000, source: @card)
    expense(-180_000, source: @cash)

    assert_equal %w[account credit_card cash], report[:kinds].map { |k| k[:kind] }
  end

  test "empty period yields zeroed structure" do
    data = report

    assert_empty data[:kinds]
    assert_equal 0.to_d, data[:total]
  end

  test "handles large amounts precisely" do
    expense(-99_999_999.99, source: @cash)

    assert_equal 99_999_999.99.to_d, report[:total]
  end
end
