# frozen_string_literal: true

module Mcp
  module Tools
    module Debts
      # GetDebtsTool
      # Credit cards and loans with their outstanding balance.
      class GetDebtsTool < Mcp::ApplicationTool
        tool_name "get_debts"
        description "List credit cards and loans with outstanding balance, installment and next payment date."
        requires_scope :read

        def call
          debts = user.money_sources.active.where(kind: %w[credit_card loan]).includes(:credit_account).order(:kind, :name)
                      .map { |source| Mcp::Presenters::DebtPresenter.new(source).as_json }

          success(debts: debts)
        end
      end
    end
  end
end
