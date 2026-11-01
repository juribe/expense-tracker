# frozen_string_literal: true

module Gmf
  # Gmf::Calculator
  # Determines whether GMF applies to a movement and how much.
  #
  # Example:
  #   Gmf::Calculator.call(user:, origin_money_source:, operation_type: :expense_payment,
  #                        date:, amount:)
  class Calculator
    RATE = BigDecimal("0.004")

    Result = Struct.new(
      :taxed, :consumes_exemption, :taxable_base, :gmf_amount,
      :covered_by_exemption, :taxable_excess, :reason,
      keyword_init: true
    ) do
      def taxed? = taxed
      def consumes_exemption? = consumes_exemption
    end

    def self.call(user:, origin_money_source:, operation_type:, date:, amount:,
                  tax_treatment: nil, bank_charged_gmf: nil)
      new(user:, origin_money_source:, operation_type:, date:, amount:,
          tax_treatment:, bank_charged_gmf:).call
    end

    def initialize(user:, origin_money_source:, operation_type:, date:, amount:,
                   tax_treatment: nil, bank_charged_gmf: nil)
      @user = user
      @origin = origin_money_source
      @operation_type = operation_type
      @date = date.to_date
      @amount = amount.to_d.abs
      @tax_treatment = tax_treatment
      @bank_charged_gmf = bank_charged_gmf
    end

    def call
      classification = @tax_treatment || OperationClassification.classify(
        operation_type: @operation_type, money_source: @origin
      )

      unless OperationClassification.taxable?(classification)
        return Result.new(taxed: false, consumes_exemption: false, taxable_base: 0.to_d,
                          gmf_amount: 0.to_d, covered_by_exemption: 0.to_d,
                          taxable_excess: 0.to_d, reason: "operación no gravada")
      end

      consumes = OperationClassification.consumes_exemption?(classification)

      # Resolve the effective account: debit cards spend their parent account.
      effective = @origin.debit_card? && @origin.parent ? @origin.parent : @origin

      # Non-exempt accounts (or accounts not marked exempt) pay GMF from the
      # first peso: they receive no independent 350 UVT exemption.
      exempt_account = MoneySource.gmf_exempt_for(@user)
      is_exempt_account = exempt_account.present? && exempt_account.id == effective.id

      if !consumes
        gmf = @amount * RATE
        return Result.new(taxed: true, consumes_exemption: false, taxable_base: @amount,
                          gmf_amount: gmf, covered_by_exemption: 0.to_d,
                          taxable_excess: @amount, reason: nil)
      end

      if !is_exempt_account
        gmf = @amount * RATE
        return Result.new(taxed: true, consumes_exemption: true, taxable_base: @amount,
                          gmf_amount: gmf, covered_by_exemption: 0.to_d,
                          taxable_excess: @amount, reason: nil)
      end

      # Exempt account: consume the monthly exemption.
      limit = Gmf::Uvt.exemption_limit(@date.year)
      accumulator = GmfMonthlyAccumulator.for(user: @user, money_source: effective, date: @date)
      already_covered = accumulator.covered_by_exemption.to_d
      available = [limit - already_covered, 0.to_d].max
      covered = [@amount, available].min
      excess = @amount - covered
      gmf = excess * RATE

      Result.new(taxed: true, consumes_exemption: true, taxable_base: @amount,
                 gmf_amount: gmf, covered_by_exemption: covered,
                 taxable_excess: excess, reason: nil)
    end
  end
end
