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

    test "rejects an expense that is already linked" do
      linked = create_expense(recurring_template_id: @template.id)

      result = RecurringAssignment.assign(
        user: @user, expense_id: linked.id, recurring_template_id: @template.id
      )

      assert result.failure?
      assert_equal "already_linked", result.message_key
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
  end
end
