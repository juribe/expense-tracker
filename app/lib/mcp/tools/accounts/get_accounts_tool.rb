# frozen_string_literal: true

module Mcp
  module Tools
    module Accounts
      # GetAccountsTool
      # Bank accounts, cash, wallets and debit cards, with their real balance.
      class GetAccountsTool < Mcp::ApplicationTool
        tool_name "get_accounts"
        description "List bank accounts, cash, wallets and debit cards."
        requires_scope :read

        KINDS = %w[account debit_card cash wallet].freeze

        arguments do
          optional(:kind).filled(:string, included_in?: KINDS)
            .description "Filter by kind: account, debit_card, cash or wallet."
        end

        def call(kind: nil)
          kinds = kind ? [ kind ] : KINDS
          accounts = user.money_sources.active.where(kind: kinds).order(:kind, :name)
                         .map { |source| Mcp::Presenters::MoneySourcePresenter.new(source).as_json }

          success(accounts: accounts)
        end
      end
    end
  end
end
