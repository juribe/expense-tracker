# frozen_string_literal: true

module Gmf
  class Reconciler
    def self.reconcile_bank_charge(expense)
      new(expense).call
    end

    def initialize(expense)
      @expense = expense
    end

    def call
      existing = Expense.where(
        user_id: @expense.user_id,
        gmf_origin_type: "Expense",
        gmf_status: "estimated",
        money_source_id: @expense.money_source_id
      ).where(date: (@expense.date - 3.days)..(@expense.date + 3.days)).first

      if existing
        existing.update!(
          amount: @expense.amount,
          gmf_status: "reconciled",
          gmf_estimated: false,
          gmf_bank_reference: @expense.id.to_s
        )
        @expense.destroy
      else
        @expense.update!(
          source: "gmf",
          gmf_status: "charged",
          gmf_estimated: false
        )
      end
    end
  end
end
