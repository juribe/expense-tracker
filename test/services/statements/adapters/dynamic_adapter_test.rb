# frozen_string_literal: true

require "test_helper"

module Statements
  module Adapters
    class DynamicAdapterTest < ActiveSupport::TestCase
      FIXTURE = Rails.root.join("test/fixtures/files/davibank_credit_card.txt")

      setup do
        @mapping = StatementFormatMapping.new(
          sections: { "expenses" => [ "Transacciones del periodo facturado", "Transacciones de periodos anteriores" ] },
          row_spec: {
            "fields" => [
              { "token" => "date", "format" => "DD/MM/YYYY" },
              { "token" => "ref", "kind" => "digits", "length" => 6 },
              { "token" => "description", "optional" => true },
              { "token" => "amount", "currency" => "$" },
              { "token" => "ignore" }
            ],
            "cancelled_pattern" => "CANCELADA"
          }
        )
        @extraction = Expenses::FileImport::Readers::Extraction.new(text: File.read(FIXTURE))
        @document = DynamicAdapter.new(@mapping).call(@extraction)
      end

      test "builds an adapter-engine document" do
        assert_equal :adapter, @document.engine
      end

      test "keeps every billed transaction" do
        assert_equal 4, @document.expense_movements.size
      end

      test "describes merchant rows by name and merchant-less rows by reference" do
        descriptions = @document.expense_movements.map { |m| m[:description] }

        assert_includes descriptions, "SMART FIT PLAZA LOS ROB"
        assert_includes descriptions, "SAO 094 VILLA CAROLINA"
        assert_includes descriptions, "MATTILDA COLOMBIA"
        assert_includes descriptions, "Compra 734987"
      end

      test "drops cancelled rows" do
        descriptions = @document.expense_movements.map { |m| m[:description] }

        assert_nil descriptions.find { |d| d.match?(/CANCELADA/i) }
      end

      test "parses amounts and dates" do
        smart_fit = @document.expense_movements.find { |m| m[:description] == "SMART FIT PLAZA LOS ROB" }

        assert_equal BigDecimal("112916"), smart_fit[:amount]
        assert_equal Date.new(2026, 9, 10), smart_fit[:date]
        assert_equal "expense", smart_fit[:type]
      end

      test "never emits income movements" do
        assert_empty @document.income_movements
      end

      test "carries no summary when the recipe has no summary selectors" do
        assert_nil @document.summary
      end

      test "extracts the period summary from the learned selectors" do
        mapping = StatementFormatMapping.new(
          sections: @mapping.sections,
          row_spec: @mapping.row_spec,
          summary_spec: {
            "total_due" => { "label" => "= Pago total" },
            "interest_charged" => { "label" => "+ Intereses corrientes" }
          }
        )

        document = DynamicAdapter.new(mapping).call(@extraction)

        assert_equal BigDecimal("3983689"), document.summary.total_due
        assert_equal BigDecimal("0"), document.summary.interest_charged
      end

      test "ignores lines without a matching row pattern" do
        text = "Transacciones del periodo facturado\n                               6017 JOSE JAVIER URI\n" \
               "    18/09/2026       734987                                    $ 24.000        1/1        $ 24.000\n"
        document = DynamicAdapter.new(@mapping).call(Expenses::FileImport::Readers::Extraction.new(text: text))

        assert_equal 1, document.expense_movements.size
      end
    end
  end
end
