# frozen_string_literal: true

module Mcp
  # ServerFactory
  # Builds a fresh, stateless fast-mcp server for one authenticated request.
  # Only tools permitted by the token scopes are registered.
  #
  # Example: Mcp::ServerFactory.build(scopes: token.scopes)
  class ServerFactory
    NAME = "yogasto"
    VERSION = "1.0.0"

    # Stored as names so development code reloading never keeps stale classes.
    TOOL_NAMES = %w[
      Mcp::Tools::Context::GetFinancialContextTool
      Mcp::Tools::Context::GetCategoriesTool
      Mcp::Tools::Context::GetMoneySourcesTool
      Mcp::Tools::Expenses::GetExpensesTool
      Mcp::Tools::Expenses::GetExpenseTool
      Mcp::Tools::Expenses::CreateExpenseTool
      Mcp::Tools::Expenses::UpdateExpenseTool
      Mcp::Tools::Expenses::DeleteExpenseTool
      Mcp::Tools::Incomes::GetIncomesTool
      Mcp::Tools::Incomes::GetIncomeTool
      Mcp::Tools::Incomes::CreateIncomeTool
      Mcp::Tools::Incomes::UpdateIncomeTool
      Mcp::Tools::Transfers::CreateTransferTool
      Mcp::Tools::Accounts::GetAccountsTool
      Mcp::Tools::Accounts::GetAccountBalancesTool
      Mcp::Tools::CreditCards::GetCreditCardsTool
      Mcp::Tools::CreditCards::GetCreditCardDetailsTool
      Mcp::Tools::CreditCards::CreateCreditCardPaymentTool
      Mcp::Tools::Debts::GetDebtsTool
      Mcp::Tools::Debts::GetDebtDetailsTool
      Mcp::Tools::Debts::CreateDebtPaymentTool
      Mcp::Tools::Pockets::GetPocketsTool
      Mcp::Tools::Pockets::GetPocketDetailsTool
      Mcp::Tools::Pockets::CreatePocketTool
      Mcp::Tools::Pockets::UpdatePocketTool
      Mcp::Tools::Pockets::AllocateToPocketTool
      Mcp::Tools::Pockets::WithdrawFromPocketTool
      Mcp::Tools::Budgets::GetBudgetsTool
      Mcp::Tools::Budgets::GetBudgetDetailsTool
      Mcp::Tools::Budgets::GetBudgetProgressTool
      Mcp::Tools::Budgets::CreateBudgetTool
      Mcp::Tools::Budgets::UpdateBudgetTool
      Mcp::Tools::SavingsGoals::GetSavingsGoalsTool
      Mcp::Tools::SavingsGoals::GetSavingsGoalDetailsTool
      Mcp::Tools::SavingsGoals::CreateSavingsGoalTool
      Mcp::Tools::SavingsGoals::UpdateSavingsGoalTool
      Mcp::Tools::SavingsGoals::ContributeToSavingsGoalTool
      Mcp::Tools::SavingsGoals::WithdrawFromSavingsGoalTool
      Mcp::Tools::Reports::GetMonthlyReportTool
      Mcp::Tools::Reports::GetExpensesByCategoryTool
      Mcp::Tools::Reports::GetIncomeVsExpensesTool
    ].freeze

    def self.build(scopes:)
      new(scopes: scopes).build
    end

    def initialize(scopes:)
      @scopes = Array(scopes).map(&:to_s)
    end

    def build
      server = ::FastMcp::Server.new(name: NAME, version: VERSION, logger: Rails.logger)
      server.transport = Mcp::HttpTransport.new(server, logger: Rails.logger)
      server.register_tools(*allowed_tools)
      server
    end

    private

    def allowed_tools
      TOOL_NAMES.map(&:constantize).select do |tool|
        scope = tool.required_scope
        scope.nil? || @scopes.include?(scope)
      end
    end
  end
end
