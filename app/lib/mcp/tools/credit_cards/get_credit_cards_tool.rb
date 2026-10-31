# frozen_string_literal: true

module Mcp
  module Tools
    module CreditCards
      # GetCreditCardsTool
      # Credit cards with limit, usage and the dates an agent needs to decide.
      class GetCreditCardsTool < Mcp::ApplicationTool
        tool_name "get_credit_cards"
        description "List credit cards with limit, used credit, available credit and payment dates."
        requires_scope :read

        def call
          cards = user.money_sources.active.where(kind: "credit_card").includes(:credit_account).order(:name)
                      .map { |source| Mcp::Presenters::CreditCardPresenter.new(source).as_json }

          success(credit_cards: cards)
        end
      end
    end
  end
end
