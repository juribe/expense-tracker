# frozen_string_literal: true

require "test_helper"

# Shared amount heuristics for file imports, email statements and image OCR.
# The same separator rule applies everywhere: 1-2 trailing digits are decimals,
# 3 digits group thousands with either comma or dot.
class ExpensesValueParsingTest < ActiveSupport::TestCase
  test "reads thousands followed by decimals as one amount" do
    assert_equal 22_209.60, Expenses::ValueParsing.parse_amount_text("22.209,60")
    assert_equal BigDecimal("22209.60"), Expenses::ValueParsing.parse_amount("22.209,60")
  end

  test "reads comma or dot with three digits as thousands" do
    assert_equal 5_400.0, Expenses::ValueParsing.parse_amount_text("5,400")
    assert_equal 5_400.0, Expenses::ValueParsing.parse_amount_text("5.400")
    assert_equal 8_500.0, Expenses::ValueParsing.parse_amount_text("8,500")
  end

  test "reads comma or dot with one or two digits as decimals" do
    assert_equal 7.02, Expenses::ValueParsing.parse_amount_text("7,02")
    assert_equal 7.02, Expenses::ValueParsing.parse_amount_text("7.02")
    assert_equal 8.5, Expenses::ValueParsing.parse_amount_text("8,5")
  end

  test "keeps the existing grouped and negative formats" do
    assert_equal 1_200_000.0, Expenses::ValueParsing.parse_amount_text("1'200.000")
    assert_equal 87_500.0, Expenses::ValueParsing.parse_amount_text("87.500")
    assert_equal BigDecimal("-1234.56"), Expenses::ValueParsing.parse_amount("-1.234,56")
  end
end
