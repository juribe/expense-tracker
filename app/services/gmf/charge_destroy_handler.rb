# frozen_string_literal: true

module Gmf
  # Gmf::ChargeDestroyHandler
  # Recalculates the month's accumulator when an automatic GMF charge is
  # deleted. The origin movement is the reference for the period; when it is
  # gone, the charge's own source and date are used. This keeps the
  # "Control del GMF" card aligned with the movements that still exist.
  class ChargeDestroyHandler
    def self.call(charge)
      new(charge).call
    end

    def initialize(charge)
      @charge = charge
    end

    def call
      if origin
        Gmf::AccumulatorRecalculator.call(
          user: @charge.user,
          money_source: origin_source,
          date: origin_date
        )
      elsif @charge.money_source
        Gmf::AccumulatorRecalculator.call(
          user: @charge.user,
          money_source: @charge.money_source,
          date: @charge.date
        )
      end
    end

    private

    def origin
      return @origin if defined?(@origin)

      @origin = find_origin
    end

    def find_origin
      case @charge.gmf_origin_type
      when "Expense" then Expense.find_by(id: @charge.gmf_origin_id)
      when "Transfer" then Transfer.find_by(id: @charge.gmf_origin_id)
      end
    end

    def origin_source
      origin.is_a?(Transfer) ? origin.from_source : origin.money_source
    end

    def origin_date
      origin.date
    end
  end
end
