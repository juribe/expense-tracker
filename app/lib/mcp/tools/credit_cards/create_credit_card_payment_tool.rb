# frozen_string_literal: true

module Mcp
  module Tools
    module CreditCards
      # CreateCreditCardPaymentTool
      # Applies a payment to a credit card through Payments::CreateManual: the
      # funding expense and its debt application are created together.
      class CreateCreditCardPaymentTool < Mcp::ApplicationTool
        include Mcp::Tools::DebtPayments::PaymentFlow

        tool_name "create_credit_card_payment"
        description "Pay a credit card from an account, cash or wallet."
        requires_scope :write

        arguments do
          required(:amount).filled.description "Positive amount."
          required(:date).filled(:string).description "ISO date (YYYY-MM-DD)."
          required(:account_id).filled(:string).description "Funding money source UUID."
          required(:credit_card_id).filled(:string).description "Credit card UUID."
          optional(:description).filled(:string).description "Short description."
          optional(:category_id).filled(:string).description "Expense category UUID (defaults to the debt payments category)."
          optional(:principal_amount).filled.description "Principal component."
          optional(:interest_amount).filled.description "Interest component."
          optional(:insurance_amount).filled.description "Insurance component."
          optional(:other_amount).filled.description "Other component."
          optional(:idempotency_key).filled(:string).description "UUID to make retries safe."
        end

        def call(amount:, date:, account_id:, credit_card_id:, description: nil, category_id: nil,
                 principal_amount: nil, interest_amount: nil, insurance_amount: nil, other_amount: nil,
                 idempotency_key: nil)
          card = user.money_sources.find(UuidParams.normalize(credit_card_id))
          unless card.credit_card?
            raise Mcp::Error.new("INVALID_CREDIT_CARD", "The selected money source is not a credit card.")
          end

          pay_debt(
            target: card,
            funding: find_money_source!(account_id),
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
