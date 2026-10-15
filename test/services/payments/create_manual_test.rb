# frozen_string_literal: true

require "test_helper"

module Payments
  # The manual payment creates BOTH the expense and its application to a debt
  # (like the statement import's payment), then lets Payments::Apply link the
  # expense to the debt's recurring payment template.
  class CreateManualTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Manual Pay", email: "manual_pay@example.com", password: "password123")
      @category = Category.create!(user: @user, name: "Vivienda")
      @account = MoneySource.create!(user: @user, name: "Ahorros", kind: "account", starting_balance: 5_000_000)
      @mortgage = MoneySource.create!(user: @user, name: "Hipotecario", kind: "loan", starting_balance: 0)
      CreditAccount.create!(money_source: @mortgage, principal_amount: 50_000_000, outstanding_balance: 30_000_000)
    end

    def create_template(amount: 1_500_000, source: @mortgage)
      RecurringTemplate.create!(
        user: @user, category: @category, kind: "expense", description: "Cuota hipoteca",
        amount: amount, frequency: "monthly", source: "manual", payment_day: 5, money_source: source
      )
    end

    def call(amount: "1.500.000", category_id: @category.id, distribution: { principal_amount: "1.500.000" }, **overrides)
      Payments::CreateManual.call(
        user: @user, money_source: @mortgage, amount: amount, date: Date.current,
        description: "Cuota hipoteca", category_id: category_id,
        funding_money_source_id: @account.id, distribution: distribution, **overrides
      )
    end

    test "creates the expense and the payment and links the recurring template" do
      template = create_template

      result = call(distribution: { principal_amount: "900.000", interest_amount: "600.000" })

      assert result.success?, result.errors.inspect
      payment = result.result
      assert_equal @mortgage.id, payment.money_source_id
      assert_equal BigDecimal("1500000"), payment.amount

      expense = payment.expense
      assert_equal @account.id, expense.money_source_id
      assert_equal "manual", expense.source
      # RecurringLink links via its own instance, so read the persisted value.
      assert_equal template.id, expense.reload.recurring_template_id
    end

    test "rolls back the expense when the distribution does not sum to the amount" do
      assert_no_difference [ "Expense.count", "Payment.count" ] do
        result = call(distribution: { principal_amount: "900.000" })

        assert result.failure?
        assert result.errors.any?
      end
    end

    test "rejects a blank category without creating anything" do
      assert_no_difference [ "Expense.count", "Payment.count" ] do
        result = call(category_id: nil)

        assert result.failure?
      end
    end

    test "rejects a non-debt target without creating anything" do
      assert_no_difference [ "Expense.count", "Payment.count" ] do
        result = Payments::CreateManual.call(
          user: @user, money_source: @account, amount: "1.500.000", date: Date.current,
          description: "Cuota", category_id: @category.id, distribution: { principal_amount: "1.500.000" }
        )

        assert result.failure?
      end
    end
  end
end
