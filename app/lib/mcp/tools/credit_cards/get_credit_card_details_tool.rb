# frozen_string_literal: true

module Mcp
  module Tools
    module CreditCards
      # GetCreditCardDetailsTool
      # One card, including its last applied payment.
      class GetCreditCardDetailsTool < Mcp::ApplicationTool
        tool_name "get_credit_card_details"
        description "Return one credit card with limit, usage, payment dates and last payment."
        requires_scope :read

        arguments do
          required(:credit_card_id).filled(:string).description "Credit card UUID."
        end

        def call(credit_card_id:)
          card = user.money_sources.includes(:credit_account).find(UuidParams.normalize(credit_card_id))
          unless card.credit_card?
            raise Mcp::Error.new("INVALID_CREDIT_CARD", "The selected money source is not a credit card.")
          end

          success(Mcp::Presenters::CreditCardPresenter.new(card, include_payment: true).as_json)
        end
      end
    end
  end
end
