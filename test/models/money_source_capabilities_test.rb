# frozen_string_literal: true

require "test_helper"

# MoneySource capabilities: what each source can be used for, derived from
# kind + sub_kind (never stored booleans).
#   payment_source       — pays expenses directly (cash, accounts, cards, wallets)
#   funding_source       — money can be disbursed from it (revolving loans only)
#   debt_payment_target  — receives debt payments (credit cards, all loans)
class MoneySourceCapabilitiesTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Capabilities User", email: "capabilities@example.com", password: "password123")
  end

  def create_source(kind: "account", sub_kind: nil, **overrides)
    @user.money_sources.create!(
      { name: "Source", kind: kind, sub_kind: sub_kind, starting_balance: 1000 }.merge(overrides)
    )
  end

  # Order-insensitive comparison for sources (by id), since scopes return
  # rows in arbitrary DB order.
  def assert_expected_sources(expected, actual)
    assert_equal expected.map(&:id).sort, Array(actual).map(&:id).sort
  end

  test "cash is a payment source and nothing else" do
    cash = create_source(kind: "cash")
    assert cash.payment_source?
    assert_not cash.funding_source?
    assert_not cash.debt_payment_target?
  end

  test "savings account is a payment source and nothing else" do
    account = create_source(kind: "account")
    assert account.payment_source?
    assert_not account.funding_source?
    assert_not account.debt_payment_target?
  end

  test "debit card and wallet are payment sources" do
    assert create_source(kind: "debit_card").payment_source?
    assert create_source(kind: "wallet").payment_source?
  end

  test "credit card is a payment source AND a debt payment target" do
    card = create_source(kind: "credit_card")
    assert card.payment_source?
    assert card.debt_payment_target?
    assert_not card.funding_source?
  end

  test "revolving loan is NOT a payment source, IS a funding source and debt target" do
    loan = create_source(kind: "loan", sub_kind: "revolving")
    assert_not loan.payment_source?
    assert loan.funding_source?
    assert loan.debt_payment_target?
  end

  test "free-investment loan is NOT a payment source, NOT a funding source, IS a debt target" do
    loan = create_source(kind: "loan", sub_kind: "personal")
    assert_not loan.payment_source?
    assert_not loan.funding_source?
    assert loan.debt_payment_target?
  end

  test "vehicle loan is only a debt payment target" do
    loan = create_source(kind: "loan", sub_kind: "vehicle")
    assert_not loan.payment_source?
    assert_not loan.funding_source?
    assert loan.debt_payment_target?
  end

  test "mortgage is only a debt payment target" do
    loan = create_source(kind: "loan", sub_kind: "mortgage")
    assert_not loan.payment_source?
    assert_not loan.funding_source?
    assert loan.debt_payment_target?
  end

  test "loan without sub_kind is a plain debt payment target (legacy rows)" do
    loan = create_source(kind: "loan")
    assert_not loan.payment_source?
    assert_not loan.funding_source?
    assert loan.debt_payment_target?
    assert_nil loan.sub_kind
  end

  test "sub_kind is normalized to lowercase and validated" do
    loan = create_source(kind: "loan", sub_kind: "REVOLVING")
    assert_equal "revolving", loan.reload.sub_kind

    invalid = @user.money_sources.build(name: "Bad Loan", kind: "loan", sub_kind: "spaceship")
    assert_not invalid.valid?
    assert_includes invalid.errors[:sub_kind], I18n.t("errors.messages.inclusion")
  end

  test "payment_sources scope collects cash, accounts and credit cards, never loans" do
    cash = create_source(kind: "cash", name: "Efectivo")
    account = create_source(kind: "account", name: "Cuenta")
    card = create_source(kind: "credit_card", name: "Tarjeta")
    create_source(kind: "loan", sub_kind: "revolving", name: "Rotativo")
    create_source(kind: "loan", sub_kind: "vehicle", name: "Vehículo")

    assert_expected_sources [ cash, account, card ], @user.money_sources.payment_sources.to_a
  end
  test "funding_sources scope includes only revolving loans" do
    revolving = create_source(kind: "loan", sub_kind: "revolving", name: "Rotativo")
    create_source(kind: "loan", sub_kind: "personal", name: "Libre Inversión")
    create_source(kind: "loan", name: "Sin tipo")
    create_source(kind: "account", name: "Cuenta")

    assert_expected_sources [ revolving ], @user.money_sources.funding_sources.to_a
  end

  test "debt_payment_targets scope includes credit cards and every loan" do
    card = create_source(kind: "credit_card", name: "Tarjeta")
    revolving = create_source(kind: "loan", sub_kind: "revolving", name: "Rotativo")
    personal = create_source(kind: "loan", sub_kind: "personal", name: "Libre Inversión")
    vehicle = create_source(kind: "loan", sub_kind: "vehicle", name: "Vehículo")
    mortgage = create_source(kind: "loan", sub_kind: "mortgage", name: "Hipotecario")

    assert_expected_sources [ card, revolving, personal, vehicle, mortgage ],
                         @user.money_sources.debt_payment_targets.to_a
  end
end
