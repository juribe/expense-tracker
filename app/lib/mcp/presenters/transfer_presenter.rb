# frozen_string_literal: true

module Mcp
  module Presenters
    # TransferPresenter
    # A movement between two money sources. Transfers are never expenses or
    # incomes, so the payload says exactly that.
    class TransferPresenter
      include Mcp::Presenters::Money

      def initialize(transfer)
        @transfer = transfer
      end

      def as_json
        {
          id: transfer.id,
          amount: money(transfer.amount),
          date: transfer.date.iso8601,
          source: { id: transfer.from_source_id, name: transfer.from_source.name },
          destination: { id: transfer.to_source_id, name: transfer.to_source.name },
          description: transfer.note
        }.compact
      end

      private

      attr_reader :transfer
    end
  end
end
