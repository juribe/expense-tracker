# frozen_string_literal: true

require "test_helper"

# Separator rules shared by every channel: a separator followed by one or two
# digits is a decimal separator; a separator followed by three digits groups
# thousands. "22.209,60" => 22209.60, "5,400" and "5.400" => 5400.
module ExpenseResolver
  module Amounts
    class ServiceTest < ActiveSupport::TestCase
      test "interprets thousands followed by a decimal comma as one amount" do
        value, confidence = Service.interpret_amount("22.209,60")

        assert_equal BigDecimal("22209.60"), value
        assert_operator confidence, :>=, 0.9
      end

      test "interprets thousands followed by a decimal dot as one amount" do
        value, = Service.interpret_amount("1,200.50")

        assert_equal BigDecimal("1200.50"), value
      end

      test "treats a comma or dot followed by one or two digits as a decimal separator" do
        assert_equal BigDecimal("7.02"), Service.interpret_amount("7,02").first
        assert_equal BigDecimal("7.02"), Service.interpret_amount("7.02").first
        assert_equal BigDecimal("50.5"), Service.interpret_amount("50,5").first
      end

      test "treats a comma or dot followed by three digits as a thousands separator" do
        assert_equal BigDecimal("5400"), Service.interpret_amount("5,400").first
        assert_equal BigDecimal("5400"), Service.interpret_amount("5.400").first
        assert_equal BigDecimal("22209"), Service.interpret_amount("22.209").first
        assert_equal BigDecimal("1200000"), Service.interpret_amount("1'200.000").first
      end

      test "scans a full amount as a single token instead of fragments" do
        amounts = Service.scan_amounts("$22.209,60 US$ 7,02")

        assert_equal [ "22.209,60", "7,02" ], amounts.map { |match| match[:raw] }
      end

      test "keeps the existing Colombian expressions intact" do
        {
          "50 mil" => BigDecimal("50000"),
          "50 lucas" => BigDecimal("50000"),
          "80k" => BigDecimal("80000"),
          "medio millon" => BigDecimal("500000"),
          "50.000" => BigDecimal("50000"),
          "cincuenta mil" => BigDecimal("50000")
        }.each do |raw, expected|
          assert_equal expected, Service.interpret_amount(raw).first, raw
        end
      end
    end
  end
end
