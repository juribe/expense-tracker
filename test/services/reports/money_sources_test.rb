# frozen_string_literal: true

require "test_helper"

class ReportsMoneySourcesTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Sources User", email: "reports_sources_test@example.com", password: "password123")
    @food = Category.create!(name: "Alimentación", is_default: true, category_type: "expense")
    @bank = @user.money_sources.create!(name: "Davibank", kind: "account", active: true, starting_balance: 1_000_000_000)
    @card = @user.money_sources.create!(name: "Visa", kind: "credit_card", active: true)
    @cash = @user.money_sources.create!(name: "Efectivo", kind: "cash", active: true, starting_balance: 1_000_000_000)
    @loan = @user.money_sources.create!(name: "Rotativo", kind: "loan", active: true)
    @other = User.create!(name: "Other", email: "reports_sources_other@example.com", password: "password123")
    @other_bank = @other.money_sources.create!(name: "Other Bank", kind: "account", active: true,
                                               starting_balance: 1_000_000_000)
    @period = Reports::Period.new(preset: "this_month", date: Date.new(2026, 9, 15))
    @filter = Reports::Filter.new(user: @user, period: @period)
  end

  def expense(amount, source:, date: Date.new(2026, 9, 10), user: @user)
    Expense.create!(user: user, category: @food, money_source: source, amount: amount,
                    date: date, description: "x")
  end

  def report(source_kind: nil, filter: @filter)
    Reports::MoneySources.new(user: @user, filter: filter, source_kind: source_kind).call
  end

  test "groups spending by source type with shares over the grand total" do
    expense(-420_000, source: @bank)
    expense(-310_000, source: @card)
    expense(-180_000, source: @cash)
    expense(-90_000, source: @other_bank, user: @other)

    data = report
    groups = data[:groups].index_by { |group| group[:key] }

    assert_equal 420_000.to_d, groups["accounts"][:total]
    assert_in_delta 46.2, groups["accounts"][:share_pct], 0.1
    assert_in_delta 34.1, groups["credit_cards"][:share_pct], 0.1
    assert_in_delta 19.8, groups["cash"][:share_pct], 0.1
    assert_equal 910_000.to_d, data[:total]
    assert_equal 3, data[:total_transactions]
    assert_equal 3, data[:sources_count]
    assert_equal "accounts", data[:top_group][:key]
    assert_equal data[:total], data[:groups].sum { |group| group[:total] }
    assert_in_delta 100.0, data[:groups].sum { |group| group[:share_pct] }, 0.2
  end

  test "combines accounts, debit cards and wallets into one accounts group" do
    debit = @user.money_sources.create!(name: "Débito", kind: "debit_card", active: true,
                                        starting_balance: 1_000_000)
    wallet = @user.money_sources.create!(name: "Nequi", kind: "wallet", active: true,
                                         starting_balance: 1_000_000)
    expense(-420_000, source: @bank)
    expense(-100_000, source: debit)
    expense(-80_000, source: wallet)

    data = report
    groups = data[:groups].index_by { |group| group[:key] }

    assert_equal 1, data[:groups].size
    assert_equal 600_000.to_d, groups["accounts"][:total]
    assert_equal 3, groups["accounts"][:sources].size
    assert_equal 3, data[:sources_count]
    assert_in_delta 70.0, groups["accounts"][:sources].find { |s| s[:id] == @bank.id }[:share_pct], 0.1
  end

  test "calculates each source percentage over its own group total" do
    debit = @user.money_sources.create!(name: "Débito", kind: "debit_card", active: true,
                                        starting_balance: 1_000_000)
    expense(-800_000, source: @bank)
    expense(-200_000, source: debit)
    expense(-500_000, source: @card)

    data = report
    groups = data[:groups].index_by { |group| group[:key] }
    bank_row = groups["accounts"][:sources].find { |source| source[:id] == @bank.id }
    debit_row = groups["accounts"][:sources].find { |source| source[:id] == debit.id }

    assert_in_delta 80.0, bank_row[:share_pct], 0.1
    assert_in_delta 20.0, debit_row[:share_pct], 0.1
    assert_in_delta 100.0, groups["credit_cards"][:sources].first[:share_pct], 0.1
    assert_in_delta 100.0, groups["accounts"][:sources].sum { |source| source[:share_pct] }, 0.2
  end

  test "lists sources inside each group sorted by spending" do
    debit = @user.money_sources.create!(name: "Débito", kind: "debit_card", active: true,
                                        starting_balance: 1_000_000)
    expense(-180_000, source: debit)
    expense(-420_000, source: @bank)
    expense(-100_000, source: @cash)

    data = report
    account = data[:groups].find { |group| group[:key] == "accounts" }
    cash = data[:groups].find { |group| group[:key] == "cash" }

    assert_equal [ "Davibank", "Débito" ], account[:sources].map { |source| source[:name] }
    assert_equal [ "Efectivo" ], cash[:sources].map { |source| source[:name] }
    assert_equal 100_000.to_d, cash[:sources].first[:total]
  end

  test "drill-down exposes the underlying transactions per source" do
    expense(-420_000, source: @bank)
    expense(-310_000, source: @card)

    data = report
    accounts = data[:groups].find { |group| group[:key] == "accounts" }
    drill = accounts[:sources].first[:scope].call

    assert_equal 1, drill.count
    assert_equal @bank.id, drill.first.money_source_id
  end

  test "credit card purchases are spending; payments toward the card are not" do
    expense(-310_000, source: @card)
    card_payment = expense(-1_400_000, source: @bank)
    Payment.create!(user: @user, expense: card_payment, money_source: @card, amount: 1_400_000,
                    principal_amount: 1_400_000)

    data = report
    groups = data[:groups].index_by { |group| group[:key] }

    assert_equal 310_000.to_d, groups["credit_cards"][:total]
    assert_nil groups["accounts"], "debt payment expense is not spending"
  end

  test "loan installment expenses with payments are not money source spending" do
    installment = expense(-2_800_000, source: @bank)
    Payment.create!(user: @user, expense: installment, money_source: @loan, amount: 2_800_000,
                    principal_amount: 2_800_000)

    assert_equal 0.to_d, report[:total]
    assert_empty report[:groups]
  end

  test "transfers are never money source spending" do
    @user.transfers.create!(from_source: @bank, to_source: @card, amount: 1_000_000,
                            date: Date.new(2026, 9, 20))

    assert_equal 0.to_d, report[:total]
    assert_empty report[:groups]
  end

  test "respects the money source filter" do
    expense(-420_000, source: @bank)
    expense(-310_000, source: @card)
    scoped_filter = Reports::Filter.new(user: @user, period: @period, credit_card_id: @card.id)

    data = report(filter: scoped_filter)

    assert_equal 310_000.to_d, data[:total]
    assert_equal 1, data[:groups].size
  end

  test "respects the category filter" do
    other_food = Category.create!(name: "Otro_#{SecureRandom.hex(4)}", category_type: "expense", user: @user)
    expense(-420_000, source: @bank)
    Expense.create!(user: @user, category: other_food, money_source: @cash, amount: -100_000,
                    date: Date.new(2026, 9, 10), description: "x")
    scoped_filter = Reports::Filter.new(user: @user, period: @period, category_id: other_food.id)

    data = report(filter: scoped_filter)

    assert_equal 100_000.to_d, data[:total]
    assert_equal %w[cash], data[:groups].map { |group| group[:key] }
  end

  test "filters by source type and falls back to all for unknown values" do
    expense(-420_000, source: @bank)
    expense(-310_000, source: @card)
    expense(-180_000, source: @cash)

    cards = report(source_kind: "credit_cards")
    assert_equal %w[credit_cards], cards[:groups].map { |group| group[:key] }
    assert_equal 310_000.to_d, cards[:total]
    assert_equal 1, cards[:total_transactions]

    cash = report(source_kind: "cash")
    assert_equal %w[cash], cash[:groups].map { |group| group[:key] }
    assert_equal 180_000.to_d, cash[:total]

    unknown = report(source_kind: "not-a-type")
    assert_equal 3, unknown[:groups].size
    assert_equal 910_000.to_d, unknown[:total]
  end

  test "groups are sorted from highest to lowest spending" do
    expense(-420_000, source: @bank)
    expense(-310_000, source: @card)
    expense(-180_000, source: @cash)

    assert_equal %w[accounts credit_cards cash], report[:groups].map { |group| group[:key] }
  end

  test "empty period yields zeroed summary without percentages" do
    data = report

    assert_empty data[:groups]
    assert_equal 0.to_d, data[:total]
    assert_equal 0, data[:total_transactions]
    assert_equal 0, data[:sources_count]
    assert_nil data[:top_group]
  end

  test "handles large amounts precisely" do
    expense(-99_999_999.99, source: @cash)

    assert_equal 99_999_999.99.to_d, report[:total]
  end
end
