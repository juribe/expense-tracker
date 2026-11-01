# frozen_string_literal: true

module Gmf
  # Gmf::ExpenseHandler
  # Integrates GMF calculation with an expense movement.
  class ExpenseHandler
    def self.call(expense)
      new(expense).call
    end

    def initialize(expense)
      @expense = expense
    end

    def call
      return if @expense.source.to_s == "gmf"
      return if @expense.money_source.nil?
      return if Gmf::BankChargeDetector.bank_charge?(@expense.description)
      return unless gmf_eligible_source?(@expense.money_source)
      return unless GmfUvtYear.exists?

      operation_type = @expense.money_source.credit_card? ? :credit_card_purchase : :expense_payment
      result = Gmf::Calculator.call(
        user: @expense.user,
        origin_money_source: @expense.money_source,
        operation_type: operation_type,
        date: @expense.date,
        amount: @expense.amount.to_d.abs
      )

      effective = effective_account

      if result.consumes_exemption?
        accumulator = GmfMonthlyAccumulator.for(user: @expense.user, money_source: effective, date: @expense.date)
        Gmf::MonthlyAccumulator.add!(
          accumulator,
          amount: result.taxable_base,
          covered: result.covered_by_exemption,
          taxable: result.taxable_excess,
          gmf: result.gmf_amount
        )
      end

      if result.gmf_amount > 0
        Gmf::ChargeCreator.call(
          user: @expense.user,
          origin: @expense,
          origin_type: "Expense",
          amount: result.gmf_amount,
          date: @expense.date,
          money_source: @expense.money_source,
          estimated: true
        )
      end
    end

    private

    def gmf_eligible_source?(source)
      %w[account debit_card].include?(source.kind)
    end

    def effective_account
      source = @expense.money_source
      source.debit_card? && source.parent ? source.parent : source
    end
  end
end
