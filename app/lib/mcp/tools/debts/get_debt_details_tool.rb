# frozen_string_literal: true

module Mcp
  module Tools
    module Debts
      # GetDebtDetailsTool
      # One credit card or loan with its repayment figures.
      class GetDebtDetailsTool < Mcp::ApplicationTool
        tool_name "get_debt_details"
        description "Return one debt with outstanding balance, installment, rate and next payment date."
        requires_scope :read

        arguments do
          required(:debt_id).filled(:string).description "Debt UUID (credit card or loan)."
        end

        def call(debt_id:)
          debt = user.money_sources.includes(:credit_account).find(UuidParams.normalize(debt_id))
          raise Mcp::Error.new("INVALID_DEBT", "The selected money source is not a debt.") unless debt.debt?

          success(Mcp::Presenters::DebtPresenter.new(debt).as_json)
        end
      end
    end
  end
end
