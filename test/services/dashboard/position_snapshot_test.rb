# frozen_string_literal: true

require "test_helper"

class Dashboard::PositionSnapshotTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Test User", email: "position_snapshot_test@example.com", password: "password123")
    @category = Category.create!(name: "Comida", is_default: true, category_type: "expense")
  end

  def snapshot
    Dashboard::PositionSnapshot.call(user: @user)
  end

  def create_source(name, kind, starting_balance: 0, **attrs)
    @user.money_sources.create!(name: name, kind: kind, starting_balance: starting_balance, active: true, **attrs)
  end

  def spend(source, amount)
    source.transactions.create!(user: @user, category: @category, amount: -amount, date: Date.today,
                                kind: "expense", source: "manual")
    source.reload
  end

  test "returns every key as zero for a user without money sources" do
    result = snapshot

    assert_equal 0, result[:accounts_balance]
    assert_equal 0, result[:savings_balance]
    assert_equal 0, result[:credit_available]
    assert_equal 0, result[:credit_debt]
    assert_equal 0, result[:loan_debt]
  end

  test "accounts_balance sums accounts, debit cards, cash and wallets only" do
    create_source("Davivienda", "account", starting_balance: 500_000)
    create_source("Débito BBVA", "debit_card", starting_balance: 300_000)
    create_source("Efectivo", "cash", starting_balance: 100_000)
    create_source("Nequi", "wallet", starting_balance: 50_000)
    create_source("Bolsillo viaje", "pocket", starting_balance: 700_000)
    create_source("Visa", "credit_card", starting_balance: -8_000_000)
    create_source("Hipotecario", "loan", starting_balance: 0)

    assert_equal BigDecimal("950_000"), snapshot[:accounts_balance]
  end

  test "accounts_balance uses the cached balance, including the reconciliation offset" do
    source = create_source("Davivienda", "account", starting_balance: 500_000)
    source.update!(balance_offset: 40_000)

    assert_equal BigDecimal("540_000"), snapshot[:accounts_balance]
  end

  test "savings_balance sums pockets only" do
    create_source("Davivienda", "account", starting_balance: 500_000)
    create_source("Emergencias", "pocket", starting_balance: 1_200_000)
    create_source("Viaje", "pocket", starting_balance: 360_000)

    assert_equal BigDecimal("1_560_000"), snapshot[:savings_balance]
  end

  test "credit_debt sums used credit of credit cards only" do
    card = create_source("Visa", "credit_card", starting_balance: 0)
    spend(card, 8_124_990)

    revolving = create_source("Rotativo", "loan", sub_kind: "revolving", starting_balance: 0)
    revolving.create_credit_account!(outstanding_balance: 3_000_000, credit_limit: 10_000_000)

    create_source("Hipotecario", "loan", sub_kind: "mortgage", starting_balance: 0)

    assert_equal BigDecimal("8_124_990"), snapshot[:credit_debt]
  end

  test "loan_debt sums outstanding balances of every loan, revolving included, falling back to the balance" do
    mortgage = create_source("Hipotecario", "loan", sub_kind: "mortgage", starting_balance: 0)
    mortgage.create_credit_account!(outstanding_balance: 67_000_000, credit_limit: 0)

    # No credit_account row: the owed number comes from the negative balance.
    create_source("Familiar", "loan", sub_kind: "personal", starting_balance: -1_000_000)

    revolving = create_source("Rotativo", "loan", sub_kind: "revolving", starting_balance: 0)
    revolving.create_credit_account!(outstanding_balance: 3_000_000, credit_limit: 10_000_000)

    create_source("Visa", "credit_card", starting_balance: -8_000_000)

    assert_equal BigDecimal("71_000_000"), snapshot[:loan_debt]
  end

  test "credit_available sums the unused credit of cards and revolving loans only" do
    card = create_source("Visa", "credit_card", starting_balance: 0)
    card.create_credit_account!(credit_limit: 10_000_000)
    spend(card, 3_000_000)

    revolving = create_source("Rotativo", "loan", sub_kind: "revolving", starting_balance: 0)
    revolving.create_credit_account!(outstanding_balance: 8_000_000, credit_limit: 10_000_000)

    # An amortizing loan has no usable line: its limit must not count as cupo.
    mortgage = create_source("Hipotecario", "loan", sub_kind: "mortgage", starting_balance: 0)
    mortgage.create_credit_account!(outstanding_balance: 67_000_000, credit_limit: 10_000_000)

    assert_equal BigDecimal("9_000_000"), snapshot[:credit_available]
  end

  test "credit_available skips sources without a credit limit" do
    card = create_source("Visa sin cupo", "credit_card", starting_balance: 0)
    spend(card, 500_000)

    assert_equal 0, snapshot[:credit_available]
  end
end
