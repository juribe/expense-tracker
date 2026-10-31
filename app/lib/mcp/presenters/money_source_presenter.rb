# frozen_string_literal: true

module Mcp
  module Presenters
    # MoneySourcePresenter
    # Compact shape for accounts, cash, cards, loans and pockets. Domain-only
    # details live in the dedicated presenters.
    class MoneySourcePresenter
      include Mcp::Presenters::Money

      def initialize(source)
        @source = source
      end

      def as_json
        {
          id: source.id,
          name: source.name,
          kind: source.kind,
          sub_kind: source.sub_kind,
          institution: source.institution_name,
          balance: money(source.balance),
          available_credit: source.debt? ? money(source.available_credit) : nil,
          used_credit: source.credit_card? ? money(source.used_credit) : nil,
          outstanding_balance: source.debt? ? money(Mcp::Presenters::DebtBalance.for(source)) : nil,
          parent_id: source.parent_id,
          payment_source: source.payment_source?,
          funding_source: source.funding_source?,
          active: source.active
        }.compact
      end

      private

      attr_reader :source
    end
  end
end
