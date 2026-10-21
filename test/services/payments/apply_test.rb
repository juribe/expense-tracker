# frozen_string_literal: true

require "test_helper"

module Payments
  # Payments::Apply binds an expense to a debt target with a manual
  # distribution. The expense_created flag records whether the expense was
  # born WITH this payment (manual modal / statement import) or already
  # existed — that flag decides what the payment revert deletes.
  class ApplyTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Apply User", email: "payments_apply@example.com", password: "password123")
      @account = @user.money_sources.create!(name: "Ahorros", kind: "account", starting_balance: 5_000_000)
      @mortgage = @user.money_sources.create!(name: "Hipotecario", kind: "loan", starting_balance: 0)
      CreditAccount.create!(money_source: @mortgage, principal_amount: 50_000_000, outstanding_balance: 30_000_000)
    end

    def create_expense
      Expense.create!(user: @user, amount: 1_500_000, description: "Cuota",
                      date: Date.current, kind: "expense", source: "manual",
                      money_source: @account)
    end

    def apply(expense, **overrides)
      Payments::Apply.call(
        user: @user, money_source: @mortgage, expense: expense,
        distribution: { principal_amount: "1.500.000" }, **overrides
      )
    end

    test "successful application without the flag leaves created_expense false" do
      result = apply(create_expense)

      assert result.success?, result.errors.inspect
      assert_not result.result.created_expense?
    end

    test "expense_created: true persists created_expense on the new payment" do
      result = apply(create_expense, expense_created: true)

      assert result.success?, result.errors.inspect
      assert result.result.created_expense?
    end

    test "an existing payment edited keeps the flag untouched" do
      result = apply(create_expense, expense_created: true)
      assert result.success?
      payment = result.result

      second = Payments::Apply.call(
        user: @user, money_source: @mortgage, expense: payment.expense,
        distribution: { principal_amount: "1.400.000", interest_amount: "100.000" },
        payment: payment
      )

      assert second.success?, second.errors.inspect
      assert payment.reload.created_expense?
    end
  end
end
