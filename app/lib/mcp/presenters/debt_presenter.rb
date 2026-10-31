# frozen_string_literal: true

module Mcp
  module Presenters
    # DebtPresenter
    # Outstanding debt, installment, rate and next payment for cards and loans.
    class DebtPresenter
      include Mcp::Presenters::Money

      def initialize(source)
        @source = source
      end

      def as_json
        {
          id: source.id,
          name: source.name,
          kind: source.kind,
          type: debt_type,
          outstanding_balance: money(outstanding_balance),
          installment_amount: money(source.installment_amount),
          installment_count: source.installment_count,
          remaining_installments: source.remaining_installments,
          interest_rate: source.interest_rate&.to_s("F"),
          interest_rate_type: source.interest_rate_type,
          next_payment_date: Mcp::NextPaymentDate.for(source.payment_due_day)&.iso8601,
          progress_pct: source.loan? ? source.repayment_progress.to_f : nil
        }.compact
      end

      private

      attr_reader :source

      def debt_type
        return "credit_card" if source.credit_card?

        source.sub_kind.presence || "loan"
      end

      def outstanding_balance
        return source.outstanding_balance if source.revolving?
        return source.outstanding_balance || [ -source.balance, 0 ].max if source.loan?

        source.used_credit
      end
    end
  end
end
