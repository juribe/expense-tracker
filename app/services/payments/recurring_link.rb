# frozen_string_literal: true

module Payments
  # Bridges the payments flow with the Día de Balance dashboard: registering a
  # debt payment should also assign the expense to the recurring payment
  # template it corresponds to, otherwise the cuadre keeps listing that
  # recurring payment as pending.
  #
  # Auto-linking is strict and non-destructive:
  # - only expenses not linked to a template yet,
  # - templates already covered by another transaction in the expense's month
  #   are never candidates (RecurringAssignment would reject period_taken),
  # - the debt source is the primary signal: when exactly one active expense
  #   template points at the paid source it wins whatever its amount (the
  #   statement payment rarely matches the printed cuota). Several templates on
  #   the same source are resolved by nearest amount within a small tolerance.
  # - when no template points at the paid source, an exact-amount match on a
  #   template without a source is accepted, but only when unambiguous.
  # Anything else stays pending and the cuadre offers manual assignment
  # instead of guessing.
  class RecurringLink
    class << self
      def call(user:, expense:, money_source: nil, assign: true)
        new(user: user, expense: expense, money_source: money_source, assign: assign).call
      end
    end

    def initialize(user:, expense:, money_source:, assign: true)
      @user = user
      @expense = expense
      @money_source = money_source
      @assign = assign
    end

    def call
      return nil unless linkable?

      template = match_template
      return template if template && !@assign
      return nil if template.nil?

      result = Expenses::RecurringAssignment.assign(
        user: @user,
        expense_id: @expense.id,
        recurring_template_id: template.id,
        # Debt-target templates are only auto-linkable from this payments
        # flow: the manual assign flows reject them.
        allow_debt_target: true
      )
      result.success? ? template : nil
    end

    private

    attr_reader :user, :money_source

    def linkable?
      @expense.present? && @expense.expense? && @expense.recurring_template_id.nil?
    end

    def match_template
      candidates = usable_templates
      return nil if candidates.empty?

      if money_source
        # The debt source is the signal: a single active template pointing at
        # the paid source is the payment's recurring expense, whatever its
        # stored amount. Amount only breaks the tie when several templates
        # share the source.
        source_candidates = candidates.where(money_source_id: money_source.id).to_a
        return source_candidates.first if source_candidates.one?
        return nearest_by_amount(source_candidates) if source_candidates.any?

        # Templates explicitly pointing at another debt must not be hijacked.
        candidates = candidates.where(money_source_id: nil)
      end

      return nil if candidates.count != 1

      candidates.first
    end

    def usable_templates
      candidates = user.recurring_templates.active.expense

      fully_paid_ids = candidates.select { |template| template.fully_paid_for_period?(month_range) }.map(&:id)

      candidates.where.not(id: fully_paid_ids)
    end

    # Same debt source: pick the amount-nearest template, but only when it is
    # close enough to be the same cuota (statement totals and unrelated
    # payments stay unlinked).
    def nearest_by_amount(candidates)
      expense_amount = @expense.amount.to_d.abs
      candidates
        .min_by { |template| (template.amount.to_d - expense_amount).abs }
        .then { |nearest| nearest if within_tolerance?(nearest.amount.to_d, expense_amount) }
    end

    def within_tolerance?(template_amount, expense_amount)
      (template_amount - expense_amount).abs <= [ template_amount * 0.05, 1_000 ].max
    end

    def month_range
      @expense.date.beginning_of_month..@expense.date.end_of_month
    end
  end
end
