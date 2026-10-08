# frozen_string_literal: true

module Credits
  module Amortization
    # Row
    # One amortization installment of a credit projection. Hold BigDecimal
    # money values; projected and actual rows share this shape so the UI and
    # simulators treat both uniformly.
    Row = Struct.new(
      :installment_number, :date, :opening_balance, :principal, :interest,
      :insurance, :other, :total_payment, :closing_balance, :projected?,
      keyword_init: true
    )
  end
end
