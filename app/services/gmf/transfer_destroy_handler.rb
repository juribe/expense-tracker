# frozen_string_literal: true

module Gmf
  class TransferDestroyHandler
    def self.call(transfer)
      money_source = MoneySource.find_by(id: transfer.from_source_id)
      if money_source
        result = Gmf::Calculator.call(
          user: transfer.user, origin_money_source: money_source,
          operation_type: :transfer, date: transfer.date,
          amount: transfer.amount.to_d
        )
        effective = money_source.debit_card? && money_source.parent ? money_source.parent : money_source
        if result.consumes_exemption?
          acc = GmfMonthlyAccumulator.find_by(
            user_id: transfer.user_id, money_source_id: effective.id,
            year: transfer.date.year, month: transfer.date.month
          )
          Gmf::MonthlyAccumulator.revert!(
            acc, amount: result.taxable_base, covered: result.covered_by_exemption,
            taxable: result.taxable_excess, gmf: result.gmf_amount
          ) if acc
        end
      end

      charge = Expense.find_by(user_id: transfer.user_id, gmf_origin_type: "Transfer", gmf_origin_id: transfer.id)
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
