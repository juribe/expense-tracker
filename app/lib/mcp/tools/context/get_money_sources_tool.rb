# frozen_string_literal: true

module Mcp
  module Tools
    module Context
      # GetMoneySourcesTool
      # Lists the sources an agent can use for an expense, income, transfer or
      # payment, including balances and their payment/funding capabilities.
      class GetMoneySourcesTool < Mcp::ApplicationTool
        tool_name "get_money_sources"
        description "List the user's money sources with balances and whether they can pay, receive or fund money."
        requires_scope :read

        arguments do
          optional(:kind).filled(:string, included_in?: MoneySource::KINDS)
            .description "Filter by kind: account, debit_card, credit_card, cash, wallet, pocket or loan."
          optional(:active_only).filled(:bool)
            .description "Only active sources (default true)."
        end

        def call(kind: nil, active_only: true)
          scope = active_only ? user.money_sources.active : user.money_sources
          scope = scope.where(kind: kind) if kind

          records = scope.order(:kind, :name).to_a
          preload_credit_accounts(records)
          sources = records.map { |source| Mcp::Presenters::MoneySourcePresenter.new(source).as_json }

          success(money_sources: sources, total: sources.size)
        end
      end
    end
  end
end
