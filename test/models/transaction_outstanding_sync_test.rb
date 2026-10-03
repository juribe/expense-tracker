# frozen_string_literal: true

require "test_helper"

# Usage of a revolving loan (crédito rotativo) recorded as expenses on the
# loan itself must raise credit_account.outstanding_balance, exactly like
# purchases on a credit card raise the card debt; Payments lower the same
# number. Statement imports rely on this whole cycle.
class TransactionOutstandingSyncTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Outstanding User", email: "outstanding_sync@example.com", password: "password123")
    @loan = @user.money_sources.create!(name: "Crédito Rotativo", kind: "loan", sub_kind: "revolving",
                                        starting_balance: 0)
    @loan.create_credit_account!(principal_amount: 50_000_000, outstanding_balance: 21_000_000)
    @loan.reload
  end

  def create_expense(amount, money_source)
    Expense.create!(user: @user, amount: amount, description: "Compra",
                    date: Date.current, kind: "expense", source: "manual",
                    money_source: money_source)
  end

  test "usage expenses on a revolving loan raise the outstanding balance" do
    create_expense(2_500_000, @loan)
    create_expense(1_500_000, @loan)

    assert_equal BigDecimal("25_000_000"), @loan.reload.credit_account.outstanding_balance.to_d
  end

  test "destroying the usage expense lowers the outstanding balance back" do
    expense = create_expense(4_000_000, @loan)
    assert_equal BigDecimal("25_000_000"), @loan.reload.credit_account.outstanding_balance.to_d

    expense.destroy

    assert_equal BigDecimal("21_000_000"), @loan.reload.credit_account.outstanding_balance.to_d
  end

  test "reassigning the expense to another source moves the outstanding balance" do
    account = @user.money_sources.create!(name: "Ahorros", kind: "account", starting_balance: 100_000)
    expense = create_expense(4_000_000, @loan)
    assert_equal BigDecimal("25_000_000"), @loan.reload.credit_account.outstanding_balance.to_d

    expense.update!(money_source: account)

    assert_equal BigDecimal("21_000_000"), @loan.reload.credit_account.outstanding_balance.to_d
  end

  test "amount changes move the outstanding balance by the difference" do
    expense = create_expense(4_000_000, @loan)

    expense.update!(amount: 4_500_000)

    assert_equal BigDecimal("25_500_000"), @loan.reload.credit_account.outstanding_balance.to_d
  end

  test "non-revolving loans, credit cards and accounts are untouched" do
    mortgage = @user.money_sources.create!(name: "Hipotecario", kind: "loan", sub_kind: "mortgage",
                                           starting_balance: 0)
    mortgage.create_credit_account!(principal_amount: 80_000_000, outstanding_balance: 40_000_000)
    card = @user.money_sources.create!(name: "Visa", kind: "credit_card", starting_balance: 0)
    card.create_credit_account!(outstanding_balance: 5_000_000, principal_amount: 5_000_000)
    account = @user.money_sources.create!(name: "Ahorros", kind: "account", starting_balance: 100_000)

    create_expense(1_000_000, mortgage)
    create_expense(2_000_000, card)
    create_expense(3_000_000, account)

    assert_equal BigDecimal("40_000_000"), mortgage.reload.credit_account.outstanding_balance.to_d
    assert_equal BigDecimal("5_000_000"), card.reload.credit_account.outstanding_balance.to_d
  end

  test "the full import cycle: usage raises, then the payment lowers the outstanding balance" do
    create_expense(4_000_000, @loan)
    assert_equal BigDecimal("25_000_000"), @loan.reload.credit_account.outstanding_balance.to_d

    funding = @user.money_sources.create!(name: "Ahorros", kind: "account", starting_balance: 10_000_000)
    category = Category.create!(name: "Pago de deuda", user: @user, category_type: "expense")
    expense = Expenses::Create.call(user: @user, amount: 1_362_179, description: "Pago rotativo",
                                    category: category,
                                    occurred_at: Date.current, source: "manual", money_source: funding)
    result = Payments::Apply.call(user: @user, money_source: @loan, expense: expense,
                                  distribution: { principal_amount: "1362179", interest_amount: "0" })

    assert result.success?
    assert_equal BigDecimal("23_637_821"), @loan.reload.credit_account.outstanding_balance.to_d
  end
end
