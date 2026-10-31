# frozen_string_literal: true

module Mcp
  module Tools
    module Debts
      # CreateDebtPaymentTool
      # Applies a payment to any debt (card or loan) through the same service
      # the web payment flow uses.
      class CreateDebtPaymentTool < Mcp::ApplicationTool
        include Mcp::Tools::DebtPayments::PaymentFlow

        tool_name "create_debt_payment"
        description "Pay a credit card or loan from an account, cash or wallet."
        requires_scope :write

        arguments do
          required(:amount).filled.description "Positive amount."
          required(:date).filled(:string).description "ISO date (YYYY-MM-DD)."
          required(:debt_id).filled(:string).description "Debt UUID (credit card or loan)."
          required(:source_id).filled(:string).description "Funding money source UUID."
          optional(:description).filled(:string).description "Short description."
          optional(:category_id).filled(:string).description "Expense category UUID (defaults to the debt payments category)."
          optional(:principal_amount).filled.description "Principal component."
          optional(:interest_amount).filled.description "Interest component."
          optional(:insurance_amount).filled.description "Insurance component."
          optional(:other_amount).filled.description "Other component."
          optional(:idempotency_key).filled(:string).description "UUID to make retries safe."
        end

        def call(amount:, date:, debt_id:, source_id:, description: nil, category_id: nil,
                 principal_amount: nil, interest_amount: nil, insurance_amount: nil, other_amount: nil,
                 idempotency_key: nil)
          debt = user.money_sources.find(UuidParams.normalize(debt_id))
          unless debt.debt_payment_target?
            raise Mcp::Error.new("INVALID_DEBT", "The selected money source is not a debt.")
          end

          pay_debt(
            target: debt,
            funding: find_money_source!(source_id),
            amount: amount,
            date: date,
            description: description,
            category_id: category_id,
            components: { principal_amount: principal_amount, interest_amount: interest_amount,
                          insurance_amount: insurance_amount, other_amount: other_amount },
            idempotency_key: idempotency_key
          )
        end
      end
    end
  end
end
