# frozen_string_literal: true

require "test_helper"

module Statements
  module Adapters
    class RowCompilerTest < ActiveSupport::TestCase
      DAVIBANK_ROWS = [
        "    18/09/2026       734987                                    $ 24.000        1/1        $ 24.000            $ 0        2,13% 28,89%",
        "    10/09/2026       900686    SMART FIT PLAZA LOS ROB         $ 112.916       1/1       $ 112.916            $ 0        2,13% 28,89%",
        "    28/08/2026       610504    CANCELADA ALKOSTO-              $ 199.900       0/1          $ 0               $ 0        2,13% 28,89%"
      ].freeze

      def row_spec
        {
          "fields" => [
            { "token" => "date", "format" => "DD/MM/YYYY" },
            { "token" => "ref", "kind" => "digits", "length" => 6 },
            { "token" => "description", "optional" => true },
            { "token" => "amount", "currency" => "$" },
            { "token" => "ignore" }
          ],
          "cancelled_pattern" => "CANCELADA"
        }
      end

      test "compiles a regexp from declarative tokens" do
        assert_kind_of Regexp, RowCompiler.compile(row_spec)
      end

      test "captures date, ref and amount from a merchant-less row" do
        match = RowCompiler.compile(row_spec).match(DAVIBANK_ROWS[0])

        assert_not_nil match
        assert_equal "18/09/2026", match[:date]
        assert_equal "734987", match[:ref]
        assert_equal "24.000", match[:amount]
        assert_nil match[:description]
      end

      test "captures the merchant description when present" do
        match = RowCompiler.compile(row_spec).match(DAVIBANK_ROWS[1])

        assert_equal "10/09/2026", match[:date]
        assert_equal "SMART FIT PLAZA LOS ROB", match[:description].strip
        assert_equal "112.916", match[:amount]
      end

      test "the amount is the first transaction value, never a later capital column" do
        match = RowCompiler.compile(row_spec).match(DAVIBANK_ROWS[2])

        assert_equal "CANCELADA ALKOSTO-", match[:description].strip
        assert_equal "199.900", match[:amount]
      end

      test "does not match a line without a leading date" do
        regexp = RowCompiler.compile(row_spec)

        assert_nil regexp.match("                               6017 JOSE JAVIER URI")
      end

      test "supports a required description token" do
        spec = row_spec.merge("fields" => [
          { "token" => "date", "format" => "DD/MM/YYYY" },
          { "token" => "description" },
          { "token" => "amount", "currency" => "$" },
          { "token" => "ignore" }
        ])
        match = RowCompiler.compile(spec).match("10/09/2026    SMART FIT PLAZA LOS ROB         $ 112.916       1/1")

        assert_equal "SMART FIT PLAZA LOS ROB", match[:description].strip
        assert_equal "112.916", match[:amount]
      end

      test "supports the YYYY-MM-DD date format" do
        spec = row_spec.merge("fields" => [
          { "token" => "date", "format" => "YYYY-MM-DD" },
          { "token" => "description" },
          { "token" => "amount" }
        ])
        match = RowCompiler.compile(spec).match("2026-09-10  DIDI FOOD  45000")

        assert_equal "2026-09-10", match[:date]
        assert_equal "DIDI FOOD", match[:description].strip
        assert_equal "45000", match[:amount]
      end

      test "raises InvalidSpec without date or amount tokens" do
        assert_raises(RowCompiler::InvalidSpec) { RowCompiler.compile("fields" => [ { "token" => "description" } ]) }
        assert_raises(RowCompiler::InvalidSpec) { RowCompiler.compile({}) }
      end
    end
  end
end
