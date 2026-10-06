# frozen_string_literal: true

module Expenses
  # Assigns ONE existing expense to an active expense recurring template, or
  # clears that assignment. Guards return message keys so the controller can
  # localize them without re-deriving the rules.
  #
  #   result = Expenses::RecurringAssignment.assign(
  #     user: user, expense_id: 1, recurring_template_id: 2, period: "2026-10"
  #   )
  #   result.success?      # false on not_found / not_expense / inactive /
  #                        # debt_target / period_mismatch / already_linked /
  #                        # period_taken
  #   result.message_key   # symbol-ish key under expenses.assign_recurring.*
  #
  # `period` (optional, "YYYY-MM") is used by the Día de Cuadre assign flow:
  # the expense must be dated inside that period, otherwise the linked
  # transaction would never clear the period's pending row. Re-assigning an
  # expense to the template it is already linked to is a no-op success.
  #
  # Templates pointing at a debt source (credit card / loan) are NOT
  # assignable here: a debt payment is a real Payment (distribution +
  # balance effects), applied from the money source page, which auto-links
  # with allow_debt_target: true. Netflix-like recurring expenses stay
  # freely assignable.
  class RecurringAssignment
    def self.assign(user:, expense_id:, recurring_template_id:, period: nil, allow_debt_target: false)
      new(user: user).send(:assign, expense_id, recurring_template_id, period, allow_debt_target)
    end

    def self.unassign(user:, expense_id:)
      new(user: user).send(:unassign, expense_id)
    end

    attr_reader :message_key

    # Template description for the localized applied/period_taken messages.
    attr_reader :description

    def initialize(user:)
      @user = user
      @message_key = nil
      @ok = false
    end

    def success?
      @ok
    end

    def failure?
      !success?
    end

    private

    attr_reader :user

    def assign(expense_id, recurring_template_id, period = nil, allow_debt_target = false)
      expense = user.expenses.find_by(id: expense_id)
      template = user.recurring_templates.find_by(id: recurring_template_id)

      return reject("not_found") if expense.nil? || template.nil?
      return reject("not_expense") if template.income?
      return reject("inactive") unless template.active?
      return reject("debt_target") if template.money_source&.debt_payment_target? && !allow_debt_target

      if period.present? && expense_date_month(expense.date) != period
        @description = expense_month_label(expense.date)
        return reject("period_mismatch")
      end

      return applied(template) if expense.recurring_template_id == template.id
      return reject("already_linked") if expense.recurring_template_id.present?

      if template.transactions.where(date: expense.date.beginning_of_month..expense.date.end_of_month).exists?
        @description = template.description
        return reject("period_taken")
      end

      expense.update!(recurring_template_id: template.id)
      applied(template)
    end

    # Clears the recurring-template assignment of a single expense; the
    # template falls back to "Pendiente" for the period the expense had
    # covered.
    def unassign(expense_id)
      expense = user.expenses.where.not(recurring_template_id: nil).find_by(id: expense_id)
      return reject("not_linked") if expense.nil?

      expense.update!(recurring_template_id: nil)
      @ok = true
      @message_key = "unlinked"
      self
    end

    def reject(message_key)
      @message_key = message_key
      self
    end

    def applied(template)
      @ok = true
      @message_key = "applied"
      @description = template.description
      self
    end

    def expense_date_month(date)
      date.strftime("%Y-%m")
    end

    def expense_month_label(date)
      month_name = I18n.t("date.month_names")[date.month]
      "#{month_name} #{date.year}"
    end
  end
end
