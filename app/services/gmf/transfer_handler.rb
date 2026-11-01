# frozen_string_literal: true

module Gmf
  # Gmf::TransferHandler
  # Integrates GMF calculation with a transfer movement.
  class TransferHandler
    def self.call(transfer)
      new(transfer).call
    end

    def initialize(transfer)
      @transfer = transfer
    end

    def call
      return if @transfer.from_source.nil?
      return unless %w[account debit_card].include?(@transfer.from_source.kind)
      return unless GmfUvtYear.exists?

      result = Gmf::Calculator.call(
        user: @transfer.user,
        origin_money_source: @transfer.from_source,
        operation_type: :transfer,
        date: @transfer.date,
        amount: @transfer.amount.to_d
      )

      effective = effective_account

      if result.consumes_exemption?
        accumulator = GmfMonthlyAccumulator.for(user: @transfer.user, money_source: effective, date: @transfer.date)
        Gmf::MonthlyAccumulator.add!(
          accumulator,
          amount: result.taxable_base,
          covered: result.covered_by_exemption,
          taxable: result.taxable_excess,
          gmf: result.gmf_amount
        )
      end

      if result.gmf_amount > 0
        Gmf::ChargeCreator.call(
          user: @transfer.user,
          origin: @transfer,
          origin_type: "Transfer",
          amount: result.gmf_amount,
          date: @transfer.date,
          money_source: @transfer.from_source,
          estimated: true
        )
      end
    end

    private

    def effective_account
      source = @transfer.from_source
      source.debit_card? && source.parent ? source.parent : source
    end
  end
end
