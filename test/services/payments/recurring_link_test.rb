# frozen_string_literal: true

require "test_helper"

module Payments
  # The payments flow must also satisfy the Día de Cuadre dashboard: a
  # registered cuota closes its recurring payment template when the match is
  # unambiguous, and stays untouched otherwise.
  class RecurringLinkTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(
        name: "Cuadre Payment Link User",
        email: "recurring_link_test@example.com",
        password: "password123"
      )
      @category = Category.create!(user: @user, name: "Servicios")
      @card = MoneySource.create!(user: @user, name: "TC Davibank", kind: "credit_card", starting_balance: 0)
      CreditAccount.create!(money_source: @card, credit_limit: 8_000_000)
      @loan = MoneySource.create!(user: @user, name: "Crédito carro", kind: "loan", starting_balance: 0)
      CreditAccount.create!(money_source: @loan, principal_amount: 50_000_000)
      @template = RecurringTemplate.create!(
        user: @user,
        category: @category,
        kind: "expense",
        description: "Tarjeta Davibank",
        amount: 1_500_000,
        frequency: "monthly",
        source: "manual",
        payment_day: 5,
        money_source: @card
      )
    end

    def build_expense(amount: 1_500_000, **attributes)
      Expense.create!(
        {
          user: @user,
          category: @category,
          description: "Pago cuota",
          amount: amount,
          kind: "expense",
          source: "manual",
          date: Date.current
        }.merge(attributes)
      )
    end

    test "links the expense to the unique matching template" do
      expense = build_expense

      template = RecurringLink.call(user: @user, expense: expense, money_source: @card)

      assert_equal @template.id, template.id
      assert_equal @template.id, expense.reload.recurring_template_id
    end

    test "same-source candidate wins the tie-break between equal amounts" do
      @loan_template = RecurringTemplate.create!(
        user: @user,
        category: @category,
        kind: "expense",
        description: "Crédito carro cuota",
        amount: 1_500_000,
        frequency: "monthly",
        source: "manual",
        payment_day: 5,
        money_source: @loan
      )
      expense = build_expense

      template = RecurringLink.call(user: @user, expense: expense, money_source: @loan)

      assert_equal @loan_template.id, template.id
    end

    test "same-source cuota within tolerance links even with a few pesos of drift" do
      @template.update!(amount: 1_008_855)
      expense = build_expense(amount: 1_008_852)

      template = RecurringLink.call(user: @user, expense: expense, money_source: @card)

      assert_equal @template.id, template.id
    end

    test "same-source amount far from the cuota stays unlinked (e.g. full statement payment)" do
      expense = build_expense(amount: 1_907_504)

      assert_nil RecurringLink.call(user: @user, expense: expense, money_source: @card)
      assert_nil expense.reload.recurring_template_id
    end

    test "no same-source template: exact amount on a sourceless template links" do
      @template.update!(money_source: nil)
      expense = build_expense

      template = RecurringLink.call(user: @user, expense: expense, money_source: @card)

      assert_equal @template.id, template.id
    end

    test "template pointing at another debt is never hijacked" do
      expense = build_expense(amount: 1_907_504) # far from @template's amount

      assert_nil RecurringLink.call(user: @user, expense: expense, money_source: @card)
    end

    test "ambiguous candidates without a source hint stay unlinked" do
      @template.update!(money_source: nil) # remove the source hint
      RecurringTemplate.create!(
        user: @user,
        category: @category,
        kind: "expense",
        description: "Otra cuota igual",
        amount: 1_500_000,
        frequency: "monthly",
        source: "manual",
        payment_day: 10,
        money_source: nil
      )
      expense = build_expense

      template = RecurringLink.call(user: @user, expense: expense, money_source: @card)

      assert_nil template
      assert_nil expense.reload.recurring_template_id
    end

    test "expense already linked to another template stays untouched" do
      expense = build_expense
      Expenses::RecurringAssignment.assign(
        user: @user, expense_id: expense.id, recurring_template_id: @template.id,
        allow_debt_target: true # pre-linked as the payments flow would do
      )

      assert_nil RecurringLink.call(user: @user, expense: expense, money_source: @card)
      assert_equal @template.id, expense.reload.recurring_template_id
    end

    test "template period already covered stays unlinked" do
      covered_expense = build_expense
      Expenses::RecurringAssignment.assign(
        user: @user, expense_id: covered_expense.id, recurring_template_id: @template.id,
        allow_debt_target: true # pre-linked as the payments flow would do
      )

      # The second expense of the month finds no usable candidate.
      second = build_expense
      assert_nil RecurringLink.call(user: @user, expense: second, money_source: @card)
      assert_nil second.reload.recurring_template_id
    end

    test "Payments::Apply registers the payment and closes the recurring template" do
      expense = build_expense
      expense.update!(money_source: @card) # cash came from the card's own apps flow

      result = Apply.call(
        user: @user,
        money_source: @card,
        expense: expense,
        distribution: { principal_amount: "1500000" }
      )

      assert result.success?
      assert_equal @template.id, expense.reload.recurring_template_id
      state = Reconciliation::State.call(@user)
      assert_equal 0, state.pending_payments_count
    end
  end
end
