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

    test "is idempotent when the same idempotency key arrives twice" do
      key = SecureRandom.uuid

      first = call(idempotency_key: key)
      assert first.success?, first.errors.inspect

      assert_no_difference [ "Expense.count", "Payment.count" ] do
        second = call(idempotency_key: key)

        assert second.success?, second.errors.inspect
        assert_equal first.result.id, second.result.id
      end
    end

    test "creates separate payments when idempotency keys differ" do
      assert_difference [ "Expense.count", "Payment.count" ], 2 do
        first = call(idempotency_key: SecureRandom.uuid)
        second = call(idempotency_key: SecureRandom.uuid)

        assert first.success?
        assert second.success?
        refute_equal first.result.id, second.result.id
      end
    end

    test "survives concurrent duplicate requests with the same idempotency key" do
      self.use_transactional_tests = false
      key = SecureRandom.uuid
      results = []
      start_gate = Queue.new

      threads = Array.new(2) do
        Thread.new do
          start_gate.push(1)
          start_gate.pop
          results << call(idempotency_key: key)
        rescue => e
          results << e
        end
      end
      threads.each(&:join)

      assert_equal 1, Expense.where(idempotency_key: key).count, "exactly one expense per key"
      assert_equal 1, Payment.count, "exactly one payment per key"
      errors = results.grep(StandardError)
      assert_empty errors, "threads raised: #{errors.map(&:message).inspect}"
      payment_ids = results.map(&:result).map(&:id).uniq
      assert_equal [ first_payment_id(key) ].uniq, payment_ids, "both requests resolve to the same payment"
    ensure
      Payment.where(money_source_id: @mortgage.id).destroy_all
      Expense.where(idempotency_key: key).destroy_all
      self.use_transactional_tests = true
    end

    def first_payment_id(key)
      Payment.joins(:expense).find_by(expense: { idempotency_key: key })&.id
    end
  end
end
