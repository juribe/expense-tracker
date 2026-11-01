# frozen_string_literal: true

module Gmf
  class ExpenseUpdateHandler
    def self.call(expense)
      return if expense.source.to_s == "gmf"
      return if Gmf::BankChargeDetector.bank_charge?(expense.description)
      return unless expense.saved_changes.key?("amount") || expense.saved_changes.key?("date") || expense.saved_changes.key?("money_source_id")

      old_money_source_id = expense.saved_change_to_money_source_id? ? expense.money_source_id_before_last_save : expense.money_source_id
      old_money_source = MoneySource.find_by(id: old_money_source_id)
      old_amount = expense.saved_change_to_amount? ? expense.amount_before_last_save : expense.amount
      old_date = expense.saved_change_to_date? ? expense.date_before_last_save : expense.date

      if old_money_source
        operation_type = old_money_source.credit_card? ? :credit_card_purchase : :expense_payment
        old_result = Gmf::Calculator.call(
          user: expense.user, origin_money_source: old_money_source,
          operation_type: operation_type, date: old_date,
          amount: old_amount.to_d.abs
        )
        effective_old = old_money_source.debit_card? && old_money_source.parent ? old_money_source.parent : old_money_source
        if old_result.consumes_exemption?
          acc = GmfMonthlyAccumulator.find_by(
            user_id: expense.user_id, money_source_id: effective_old.id,
            year: old_date.year, month: old_date.month
          )
          Gmf::MonthlyAccumulator.revert!(
            acc, amount: old_result.taxable_base, covered: old_result.covered_by_exemption,
            taxable: old_result.taxable_excess, gmf: old_result.gmf_amount
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

      Gmf::ExpenseHandler.call(expense)
    end
  end
end
