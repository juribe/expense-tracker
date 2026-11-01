# frozen_string_literal: true

module Gmf
  class ExpenseDestroyHandler
    def self.call(expense)
      return if expense.source.to_s == "gmf"
      return if Gmf::BankChargeDetector.bank_charge?(expense.description)

      money_source = MoneySource.find_by(id: expense.money_source_id)
      if money_source
        operation_type = money_source.credit_card? ? :credit_card_purchase : :expense_payment
        result = Gmf::Calculator.call(
          user: expense.user, origin_money_source: money_source,
          operation_type: operation_type, date: expense.date,
          amount: expense.amount.to_d.abs
        )
        effective = money_source.debit_card? && money_source.parent ? money_source.parent : money_source
        if result.consumes_exemption?
          acc = GmfMonthlyAccumulator.find_by(
            user_id: expense.user_id, money_source_id: effective.id,
            year: expense.date.year, month: expense.date.month
          )
          Gmf::MonthlyAccumulator.revert!(
            acc, amount: result.taxable_base, covered: result.covered_by_exemption,
            taxable: result.taxable_excess, gmf: result.gmf_amount
          ) if acc
        end
      end

      charge = Expense.find_by(user_id: expense.user_id, gmf_origin_type: "Expense", gmf_origin_id: expense.id)
      if charge
        if charge.gmf_estimated?
          charge.destroy
        else
          charge.update!(gmf_origin_type: nil, gmf_origin_id: nil, gmf_status: "orphaned")
        end
      end
    end
  end
end
