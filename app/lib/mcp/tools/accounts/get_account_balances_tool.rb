# frozen_string_literal: true

module Mcp
  module Tools
    module Accounts
      # GetAccountBalancesTool
      # Liquid balances plus their total. Debts and pockets are excluded so the
      # total is real spendable money.
      class GetAccountBalancesTool < Mcp::ApplicationTool
        tool_name "get_account_balances"
        description "Return liquid account balances and their total."
        requires_scope :read

        KINDS = Mcp::Tools::Accounts::GetAccountsTool::KINDS

        def call
          sources = user.money_sources.active.where(kind: KINDS).order(:kind, :name)
          accounts = sources.map { |source| Mcp::Presenters::MoneySourcePresenter.new(source).as_json }
          total = sources.sum { |source| source.balance }

          success(
            accounts: accounts,
            total_liquid: Mcp::Presenters::Money.money(total)
          )
        end
      end
    end
  end
end
