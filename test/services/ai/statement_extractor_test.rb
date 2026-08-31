# frozen_string_literal: true

require "test_helper"

module Ai
  class StatementExtractorTest < ActiveSupport::TestCase
    def parse(raw)
      Ai::StatementExtractor.parse(raw)
    end

    test "normalizes sources and transactions from a valid payload" do
      data = parse(
        "sources" => [
          { "kind" => "account", "name" => "Cuenta de Ahorros", "bank" => "Bancolombia",
            "sub_kind" => "savings", "balance" => "5.420.000" },
          { "kind" => "credit_card", "name" => "Visa", "bank" => "Davivienda",
            "card_last_four" => "8976", "credit_limit" => "10.000.000", "balance" => "2.180.000" }
        ],
        "transactions" => [
          { "date" => "2026-08-23", "description" => "Restaurante XYZ", "amount" => "48.500",
            "type" => "compra", "category" => "restaurants", "confidence" => 0.98 }
        ]
      )

      assert_equal 2, data[:sources].length
      savings = data[:sources].first
      assert_equal BigDecimal("5420000"), savings[:balance]
      card = data[:sources].second
      assert_equal "8976", card[:card_last_four]
      assert_equal BigDecimal("10000000"), card[:credit_limit]
      assert_equal BigDecimal("2180000"), card[:balance]

      transaction = data[:transactions].first
      assert_equal "expense", transaction[:type]
      assert_equal BigDecimal("48500"), transaction[:amount]
    end

    test "drops unsupported kinds and empty entries" do
      data = parse(
        "sources" => [
          { "kind" => "account", "name" => "Savings", "bank" => "Bancolombia" },
          { "kind" => "crypto", "name" => "Wallet" },
          { "kind" => "account", "name" => "", "bank" => "" }
        ]
      )
      assert_equal [ "Savings" ], data[:sources].map { |source| source[:name] }
    end

    test "normalizes card last four to exactly four digits" do
      data = parse("sources" => [ { "kind" => "credit_card", "name" => "Visa", "bank" => "Bank", "card_last_four" => "12345678" } ])
      assert_equal "5678", data[:sources].first[:card_last_four]
    end

    test "raises when no financial sources are extracted" do
      assert_raises(Ai::StatementExtractor::ExtractionError) { parse("sources" => []) }
      assert_raises(Ai::StatementExtractor::ExtractionError) { parse({}) }
      assert_raises(Ai::StatementExtractor::ExtractionError) { parse("transactions" => []) }
    end

    test "call fails cleanly without an API key configured" do
      result = with_env({ "MISTRAL_API_KEY" => nil }) do
        Ai::StatementExtractor.new.call(text: "statement")
      end
      assert_not result[:ok?]
      assert_match(/not configured/, result[:error])
    end
  end
end
