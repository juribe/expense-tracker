# frozen_string_literal: true

require "test_helper"

module Expenses
  class RecurringAssignmentTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "RA User", email: "recurring_assignment@example.com", password: "password123")
      @category = Category.create!(name: "Vivienda", user: @user, is_default: false, category_type: "expense")
      @expense = Expense.create!(
        user: @user, category: @category, amount: 10_000, description: "Alquiler",
        date: Date.new(2026, 3, 10), source: "manual"
      )
      @template = @user.recurring_templates.create!(
        category: @category, kind: "expense", amount: 10_000,
        description: "Arriendo", payment_day: 5, source: "manual"
      )
    end

    test "assigns an unlinked expense to an active expense template" do
      result = RecurringAssignment.assign(
        user: @user, expense_id: @expense.id, recurring_template_id: @template.id
      )

      assert result.success?
      assert_equal @template.id, @expense.reload.recurring_template_id
      assert_equal "applied", result.message_key
    end

    test "rejects a template that is an income template" do
      income_template = @user.recurring_templates.create!(
        category: @category, kind: "income", amount: 10_000,
        description: "Salario", payment_day: 1, source: "manual"
      )

      result = RecurringAssignment.assign(
        user: @user, expense_id: @expense.id, recurring_template_id: income_template.id
      )

      assert result.failure?
      assert_equal "not_expense", result.message_key
      assert_nil @expense.reload.recurring_template_id
    end

    test "rejects an inactive template" do
      @template.update!(active: false)

      result = RecurringAssignment.assign(
        user: @user, expense_id: @expense.id, recurring_template_id: @template.id
      )

      assert result.failure?
      assert_equal "inactive", result.message_key
    end

    test "assigning the same expense twice succeeds without changing the link" do
      result_one = RecurringAssignment.assign(
        user: @user, expense_id: @expense.id, recurring_template_id: @template.id
      )
      result_two = RecurringAssignment.assign(
        user: @user, expense_id: @expense.id, recurring_template_id: @template.id
      )

      assert result_one.success?
      assert result_two.success?
      assert_equal "applied", result_two.message_key
      assert_equal @template.id, @expense.reload.recurring_template_id
    end

    test "rejects an expense already linked to a different template" do
      other_template = @user.recurring_templates.create!(
        category: @category, kind: "expense", amount: 12_000,
        description: "Administración", payment_day: 10, source: "manual"
      )
      @expense.update!(recurring_template_id: other_template.id)

      result = RecurringAssignment.assign(
        user: @user, expense_id: @expense.id, recurring_template_id: @template.id
      )

      assert result.failure?
      assert_equal "already_linked", result.message_key
      assert_equal other_template.id, @expense.reload.recurring_template_id
    end

    test "rejects an expense dated outside the requested period" do
      result = RecurringAssignment.assign(
        user: @user, expense_id: @expense.id, recurring_template_id: @template.id,
        period: "2026-04"
      )

      assert result.failure?
      assert_equal "period_mismatch", result.message_key
      assert_nil @expense.reload.recurring_template_id
    end

    test "rejects debt-target templates in the manual assign flows" do
      loan = MoneySource.create!(user: @user, name: "Crédito carro", kind: "loan")
      debt_template = @user.recurring_templates.create!(
        category: @category, kind: "expense", amount: 10_000,
        description: "Cuota carro", payment_day: 5, source: "manual",
        money_source: loan
      )

      result = RecurringAssignment.assign(
        user: @user, expense_id: @expense.id, recurring_template_id: debt_template.id
      )

      assert result.failure?
      assert_equal "debt_target", result.message_key
      assert_nil @expense.reload.recurring_template_id
    end

    test "allows debt-target assignment when it comes from the payments flow" do
      loan = MoneySource.create!(user: @user, name: "Crédito carro", kind: "loan")
      debt_template = @user.recurring_templates.create!(
        category: @category, kind: "expense", amount: 10_000,
        description: "Cuota carro", payment_day: 5, source: "manual",
        money_source: loan
      )

      result = RecurringAssignment.assign(
        user: @user, expense_id: @expense.id, recurring_template_id: debt_template.id,
        allow_debt_target: true
      )

      assert result.success?
      assert_equal debt_template.id, @expense.reload.recurring_template_id
    end

    test "allows non-debt money-source templates in the manual assign flows" do
      account = MoneySource.create!(user: @user, name: "Davibank", kind: "account")
      account_template = @user.recurring_templates.create!(
        category: @category, kind: "expense", amount: 10_000,
        description: "Internet desde Davibank", payment_day: 8, source: "manual",
        money_source: account
      )

      result = RecurringAssignment.assign(
        user: @user, expense_id: @expense.id, recurring_template_id: account_template.id
      )

      assert result.success?
      assert_equal account_template.id, @expense.reload.recurring_template_id
    end

    test "accepts an expense dated inside the requested period" do
      result = RecurringAssignment.assign(
        user: @user, expense_id: @expense.id, recurring_template_id: @template.id,
        period: "2026-03"
      )

      assert result.success?
      assert_equal @template.id, @expense.reload.recurring_template_id
    end

    test "rejects when the template already covers the expense month" do
      create_expense(recurring_template_id: @template.id, date: Date.new(2026, 3, 20))

      result = RecurringAssignment.assign(
        user: @user, expense_id: @expense.id, recurring_template_id: @template.id
      )

      assert result.failure?
      assert_equal "period_taken", result.message_key
      assert_nil @expense.reload.recurring_template_id
    end

    test "rejects unknown expense or template" do
      result = RecurringAssignment.assign(user: @user, expense_id: 999_999, recurring_template_id: @template.id)

      assert result.failure?
      assert_equal "not_found", result.message_key
    end

    test "unassign clears the template link" do
      create_expense(recurring_template_id: @template.id)

      result = RecurringAssignment.unassign(user: @user, expense_id: @expense.id)

      assert result.failure?
      assert_equal "not_linked", result.message_key
    end

    def create_expense(**overrides)
      Expense.create!(
        {
          user: @user, category: @category, amount: 10_000, description: "Gasto",
          date: Date.new(2026, 3, 10), source: "manual"
        }.merge(overrides)
      )
    end

    test "period keys accept pay-cycle starts: inside the cycle passes" do
      @user.update!(financial_cycle_start_day: 20)
      expense = create_expense(date: Date.new(2026, 11, 3))

      result = RecurringAssignment.assign(user: @user, expense_id: expense.id,
                                          recurring_template_id: @template.id, period: "2026-10-20")

      assert result.success?
    end

    test "period keys reject expenses dated outside the cycle" do
      @user.update!(financial_cycle_start_day: 20)
      expense = create_expense(date: Date.new(2026, 10, 5))

      result = RecurringAssignment.assign(user: @user, expense_id: expense.id,
                                          recurring_template_id: @template.id, period: "2026-10-20")

      assert result.failure?
      assert_equal "period_mismatch", result.message_key
    end
  end
end
