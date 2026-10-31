# frozen_string_literal: true

module Mcp
  module Presenters
    # TransactionPresenter
    # One expense or income with its category and money source references.
    class TransactionPresenter
      include Mcp::Presenters::Money

      def initialize(transaction)
        @transaction = transaction
      end

      def as_json
        {
          id: transaction.id,
          kind: transaction.kind,
          amount: money(transaction.amount.abs),
          date: transaction.date.iso8601,
          description: transaction.description,
          category: reference(transaction.category),
          money_source: reference(transaction.money_source),
          source: transaction.source
        }
      end

      private

      attr_reader :transaction

      def reference(record)
        return nil if record.nil?

        { id: record.id, name: record.name }
      end
    end
  end
end
