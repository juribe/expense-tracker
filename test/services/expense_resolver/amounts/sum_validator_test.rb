# frozen_string_literal: true

require "test_helper"

module ExpenseResolver
  module Amounts
    # SumValidator: validates AI-merged amounts against the itemized amounts
    # in the entry's own text. Mismatches are flagged, never rewritten.
    class SumValidatorTest < ActiveSupport::TestCase
      def validate(amount, text)
        SumValidator.call(amount: amount, text: text)
      end

      test "flags a merged amount that disagrees with the multiplier sum" do
        result = validate(47_000, "Tres cafés de 8.500 cada uno y un sándwich de 22.000")

        assert result.mismatch?
        assert_equal 47_000, result.model_amount.to_i
        assert_equal 47_500, result.expected_total.to_i
      end

      test "accepts a merged amount matching the multiplier sum" do
        refute validate(47_500, "Tres cafés de 8.500 cada uno y un sándwich de 22.000").mismatch?
      end

      test "accepts a merged tip total" do
        refute validate(82_000, "Almuerzo 72.000 más 10.000 de propina, pagado con tarjeta.").mismatch?
      end

      test "accepts an explicit total alongside its items" do
        refute validate(
          180_000,
          "Compré mercado por 180.000: 120.000 de comida y 60.000 de productos de limpieza."
        ).mismatch?
      end

      test "accepts a corrected amount that matches one of the itemized values" do
        refute validate(160_000, "Compré zapatos por 180.000, bueno, fueron 160.000 al final, con Infinite.").mismatch?
      end

      test "skips fragments without an aggregation context" do
        refute validate(32_000, "Didi 32.000").mismatch?
      end

      test "skips a blank model amount" do
        refute validate(nil, "Tres cafés de 8.500 cada uno y un sándwich de 22.000").mismatch?
      end

      test "handles digits as quantities" do
        result = validate(18_000, "2 almuerzos de 12.000 cada uno")

        assert result.mismatch?
        assert_equal 24_000, result.expected_total.to_i
      end

      test "flags a unit price kept instead of the quantity total" do
        result = validate(8_500, "Tres cafés de 8.500 cada uno.")

        assert result.mismatch?
        assert_equal 25_500, result.expected_total.to_i
      end

      test "accepts the correct quantity total for a single group" do
        refute validate(25_500, "Tres cafés de 8.500 cada uno.").mismatch?
      end

      test "reads quantities without cada uno as multiplier groups" do
        refute validate(58_000, "Dos hamburguesas de 25.000 y una gaseosa de 8.000.").mismatch?

        result = validate(33_000, "Dos hamburguesas de 25.000 y una gaseosa de 8.000.")

        assert result.mismatch?
        assert_equal 58_000, result.expected_total.to_i
      end

      test "reads 'a' as the price connector with feminine cada una" do
        refute validate(140_000, "Cuatro personas comimos a 35.000 cada una.").mismatch?

        result = validate(35_000, "Cuatro personas comimos a 35.000 cada una.")

        assert result.mismatch?
        assert_equal 140_000, result.expected_total.to_i
      end
    end
  end
end
