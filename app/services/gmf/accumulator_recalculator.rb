# frozen_string_literal: true

module Gmf
  # Gmf::AccumulatorRecalculator
  # Rebuilds one calendar month's GMF accumulator from the movements that
  # still exist. Used after deletions/edits and after an automatic GMF charge
  # is deleted, so the "Control del GMF" stays in sync and never keeps stale
  # totals. The replay respects the account's current exemption state.
  #
  # Example:
  #   result = Gmf::AccumulatorRecalculator.call(user:, money_source:, date:)
  #   result.accumulator
  #   result.target_result
  class AccumulatorRecalculator
    Result = Struct.new(:accumulator, :target_result, keyword_init: true)
    ELIGIBLE_KINDS = %w[account debit_card].freeze

    def self.call(user:, money_source:, date:, target: nil)
      new(user:, money_source:, date:, target:).call
    end

    def initialize(user:, money_source:, date:, target: nil)
      @user = user
      @money_source = money_source
      @date = date.to_date
      @target = target
    end

    def call
      return empty_result unless recalculable?

      accumulator = GmfMonthlyAccumulator.for(user: @user, money_source: effective_source, date: @date)
      target_result = nil

      ActiveRecord::Base.transaction do
        accumulator.lock!
        accumulator.update!(total_debits: 0, covered_by_exemption: 0, taxable: 0, gmf_generated: 0)

        movements.each do |movement|
          result = calculate(movement)
          next unless result.consumes_exemption?

          Gmf::MonthlyAccumulator.add!(
            accumulator,
            amount: result.taxable_base,
            covered: result.covered_by_exemption,
            taxable: result.taxable_excess,
            gmf: result.gmf_amount
          )
          target_result = result if movement.record == @target
        end
      end

      Result.new(accumulator: accumulator, target_result: target_result)
    end

    private

    Movement = Struct.new(:record, :source, :operation_type, :amount, :date, keyword_init: true)

    def empty_result
      Result.new(accumulator: nil, target_result: nil)
    end

    def recalculable?
      @date.present? && effective_source.present? &&
        ELIGIBLE_KINDS.include?(effective_source.kind) &&
        GmfUvtYear.exists?
    end

    def effective_source
      return @effective_source if defined?(@effective_source)

      @effective_source = debit_card_parent || @money_source
    end

    def debit_card_parent
      @money_source.parent if @money_source&.debit_card? && @money_source.parent
    end

    def source_ids
      @source_ids ||= [ effective_source.id ] +
                      effective_source.children.where(kind: "debit_card").pluck(:id)
    end

    def movements
      @movements ||= (expense_movements + transfer_movements)
                     .sort_by { |movement| [ movement.date, movement.record.created_at, movement.record.id ] }
    end

    def expense_movements
      range = Gmf::Period.range(@date.year, @date.month)
      @user.expenses
           .where(date: range, money_source_id: source_ids)
           .where.not(source: "gmf")
           .reject { |expense| Gmf::BankChargeDetector.bank_charge?(expense.description) }
           .map do |expense|
        Movement.new(
          record: expense,
          source: expense.money_source,
          operation_type: expense.money_source.credit_card? ? :credit_card_purchase : :expense_payment,
          amount: expense.amount.to_d.abs,
          date: expense.date
        )
      end
    end

    def transfer_movements
      range = Gmf::Period.range(@date.year, @date.month)
      @user.transfers
           .where(date: range, from_source_id: source_ids)
           .map do |transfer|
        Movement.new(
          record: transfer,
          source: transfer.from_source,
          operation_type: :transfer,
          amount: transfer.amount.to_d,
          date: transfer.date
        )
      end
    end

    def calculate(movement)
      Gmf::Calculator.call(
        user: @user,
        origin_money_source: movement.source,
        operation_type: movement.operation_type,
        date: movement.date,
        amount: movement.amount
      )
    end
  end
end
