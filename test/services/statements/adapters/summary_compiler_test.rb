# frozen_string_literal: true

require "test_helper"

module Statements
  module Adapters
    class SummaryCompilerTest < ActiveSupport::TestCase
      FIXTURE = Rails.root.join("test/fixtures/files/davibank_credit_card.txt")

      setup do
        @text = File.read(FIXTURE)
      end

      test "extracts amounts and dates from the learned selectors" do
        spec = {
          "total_due" => { "label" => "= Pago total" },
          "min_payment" => { "label" => "= Pago mínimo" },
          "interest_charged" => { "label" => "+ Intereses corrientes" },
          "due_date" => { "label" => "Fecha de pago" }
        }

        summary = SummaryCompiler.compile(spec, text: @text)

        assert_equal BigDecimal("3983689"), summary.total_due
        assert_equal BigDecimal("3983689"), summary.min_payment
        assert_equal BigDecimal("0"), summary.interest_charged
        assert_equal Date.new(2026, 10, 7), summary.due_date
      end

      test "supports nth to pick a later match" do
        spec = { "statement_date" => { "label" => "Período facturado", "nth" => 2 } }

        summary = SummaryCompiler.compile(spec, text: @text)

        assert_equal Date.new(2026, 9, 18), summary.statement_date
      end

      test "returns nil when no selector resolves" do
        assert_nil SummaryCompiler.compile({ "total_due" => { "label" => "Nope" } }, text: @text)
      end

      test "ignores selectors without a label" do
        assert_nil SummaryCompiler.compile({ "total_due" => { "format" => "amount" } }, text: @text)
      end

      test "returns nil for a blank spec" do
        assert_nil SummaryCompiler.compile({}, text: @text)
        assert_nil SummaryCompiler.compile(nil, text: @text)
      end
    end
  end
end
