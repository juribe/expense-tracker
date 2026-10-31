# frozen_string_literal: true

module Mcp
  module Presenters
    # DebtBalance
    # The positive amount owed by a debt source. Amortizing loans keep their
    # debt in credit_account.outstanding_balance; cards and revolving lines
    # use used_credit.
    module DebtBalance
      module_function

      def for(source)
        return source.outstanding_balance if source.revolving?
        return source.outstanding_balance || [ -source.balance, 0 ].max if source.loan?

        source.used_credit
      end
    end
  end
end
