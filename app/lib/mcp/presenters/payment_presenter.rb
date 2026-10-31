# frozen_string_literal: true

module Mcp
  module Presenters
    # PaymentPresenter
    # A debt payment: the funding expense plus its application to the debt.
    class PaymentPresenter
      include Mcp::Presenters::Money

      def initialize(payment)
        @payment = payment
      end

      def as_json
        {
          id: payment.id,
          amount: money(payment.amount),
          date: payment.date.iso8601,
          debt: { id: payment.money_source.id, name: payment.money_source.name, kind: payment.money_source.kind },
          expense: { id: payment.expense.id, description: payment.expense.description },
          funding_source: funding_source,
          principal_amount: money(payment.principal_amount),
          interest_amount: money(payment.interest_amount),
          insurance_amount: money(payment.insurance_amount),
          other_amount: money(payment.other_amount),
          source: payment.source
        }
      end

      private

      attr_reader :payment

      def funding_source
        source = payment.expense.money_source
        return nil if source.nil?

        { id: source.id, name: source.name }
      end
    end
  end
end
