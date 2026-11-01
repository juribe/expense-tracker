# frozen_string_literal: true

module Gmf
  # Gmf::MonthlyAccumulator
  # Service to add/revert contributions to a persisted monthly accumulator.
  #
  # Example: Gmf::MonthlyAccumulator.add!(accumulator, amount:, covered:, taxable:, gmf:)
  module MonthlyAccumulator
    def self.add!(accumulator, amount:, covered:, taxable:, gmf:)
      accumulator.with_lock do
        accumulator.total_debits = accumulator.total_debits.to_d + amount.to_d
        accumulator.covered_by_exemption = accumulator.covered_by_exemption.to_d + covered.to_d
        accumulator.taxable = accumulator.taxable.to_d + taxable.to_d
        accumulator.gmf_generated = accumulator.gmf_generated.to_d + gmf.to_d
        accumulator.save!
      end
    end

    def self.revert!(accumulator, amount:, covered:, taxable:, gmf:)
      accumulator.with_lock do
        accumulator.total_debits = [accumulator.total_debits.to_d - amount.to_d, 0.to_d].max
        accumulator.covered_by_exemption = [accumulator.covered_by_exemption.to_d - covered.to_d, 0.to_d].max
        accumulator.taxable = [accumulator.taxable.to_d - taxable.to_d, 0.to_d].max
        accumulator.gmf_generated = [accumulator.gmf_generated.to_d - gmf.to_d, 0.to_d].max
        accumulator.save!
      end
    end
  end
end
