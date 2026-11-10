# frozen_string_literal: true

module Gmf
  class TransferDestroyHandler
    def self.call(transfer)
      if transfer.from_source
        Gmf::AccumulatorRecalculator.call(
          user: transfer.user, money_source: transfer.from_source, date: transfer.date
        )
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
