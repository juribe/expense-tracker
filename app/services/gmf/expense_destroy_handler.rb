# frozen_string_literal: true

module Gmf
  class ExpenseDestroyHandler
    def self.call(expense)
      return if expense.source.to_s == "gmf"
      return if Gmf::BankChargeDetector.bank_charge?(expense.description)

      money_source = MoneySource.find_by(id: expense.money_source_id)
      if money_source
        Gmf::AccumulatorRecalculator.call(
          user: expense.user, money_source: money_source, date: expense.date
        )
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
