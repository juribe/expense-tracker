# frozen_string_literal: true

module Mcp
  module Presenters
    # CreditCardPresenter
    # Limit, usage, availability and payment dates for a credit card.
    class CreditCardPresenter
      include Mcp::Presenters::Money

      def initialize(source, include_payment: false)
        @source = source
        @include_payment = include_payment
      end

      def as_json
        {
          id: source.id,
          name: source.name,
          institution: source.institution_name,
          credit_limit: money(source.credit_limit),
          used_credit: money(source.used_credit),
          available_credit: money(source.available_credit),
          utilization_pct: source.credit_utilization.to_f,
          statement_day: source.statement_day,
          payment_due_day: source.payment_due_day,
          next_payment_date: Mcp::NextPaymentDate.for(source.payment_due_day)&.iso8601,
          last_payment: last_payment
        }.compact
      end

      private

      attr_reader :source

      def last_payment
        return nil unless @include_payment

        payment = source.payments.order(date: :desc).first
        return nil if payment.nil?

        { id: payment.id, date: payment.date.iso8601, amount: money(payment.amount) }
      end
    end
  end
end
