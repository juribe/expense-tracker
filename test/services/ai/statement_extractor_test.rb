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

    test "stores only the last four digits of an account number" do
      data = parse("sources" => [ { "kind" => "account", "name" => "Cuenta de Ahorros",
                                    "bank" => "Bancolombia", "identifier" => "00112345689" } ])
      source = data[:sources].first
      assert_equal "5689", source[:identifier]
      assert_equal "5689", source[:card_last_four]
    end

    test "keeps the loan principal amount (valor desembolsado)" do
      data = parse("sources" => [ { "kind" => "loan", "name" => "Libre Inversión",
                                    "bank" => "Bancolombia", "principal_amount" => "8.000.000",
                                    "outstanding_balance" => "6.000.000", "installment_count" => "48 cuotas",
                                    "installments_paid" => "Cuota 12" } ])
      source = data[:sources].first
      assert_equal BigDecimal("8000000"), source[:principal_amount]
      assert_equal BigDecimal("6000000"), source[:outstanding_balance]
      assert_equal 48, source[:installment_count]
      assert_equal 12, source[:installments_paid]
    end

    test "parses Colombian number formats" do
      data = parse("sources" => [
        { "kind" => "account", "name" => "A", "bank" => "B", "balance" => "67.429.112,92" },
        { "kind" => "account", "name" => "C", "bank" => "D", "balance" => "1.234.567" },
        { "kind" => "account", "name" => "E", "bank" => "F", "balance" => "1234,92" },
        { "kind" => "account", "name" => "G", "bank" => "H", "balance" => "$ 5.420.000 COP" }
      ])
      balances = data[:sources].map { |s| s[:balance] }
      assert_equal BigDecimal("67429112.92"), balances[0]
      assert_equal BigDecimal("1234567"), balances[1]
      assert_equal BigDecimal("1234.92"), balances[2]
      assert_equal BigDecimal("5420000"), balances[3]
    end

    test "repairs digit-soup amounts using the statement text" do
      # AI concatenates "19.877.599,71" into 1987759971; the text still shows
      # the formatted amount, so the parser must restore the decimals.
      raw = { "sources" => [ { "kind" => "credit_card", "name" => "Crédito Rotativo",
                               "bank" => "Davibank", "balance" => 1987759971 } ] }
      data = Ai::StatementExtractor.parse(raw, text: "Saldo actual 19.877.599,71 al corte")
      assert_equal BigDecimal("19877599.71"), data[:sources].first[:balance]
    end

    test "keeps genuinely large whole amounts that match the text" do
      raw = { "sources" => [ { "kind" => "loan", "name" => "Libre Inversión",
                               "bank" => "Bancolombia", "principal_amount" => 1987759971 } ] }
      data = Ai::StatementExtractor.parse(raw, text: "Valor desembolsado 1.987.759.971")
      assert_equal BigDecimal("1987759971"), data[:sources].first[:principal_amount]
    end

    test "instructs the AI to classify revolving credit lines as loans" do
      prompt = Ai::StatementExtractor.new.send(:system_prompt)
      assert_match(/crédito rotativo/i, prompt)
      assert_match(%r{revolving.*loan}im, prompt)
      assert_match(/NEVER a credit card/i, prompt)
    end

    test "truncates a labeled account number to its last four digits" do
      raw = { "sources" => [ { "kind" => "account", "name" => "Ahorros", "bank" => "Bancolombia" } ] }
      data = Ai::StatementExtractor.parse(raw, text: "Número de cuenta: 9876543210")
      source = data[:sources].first
      assert_equal "3210", source[:identifier]
      assert_equal "3210", source[:card_last_four]
    end

    test "fills a missing loan identifier from a labeled contract number" do
      raw = { "sources" => [ { "kind" => "loan", "name" => "Crédito Hipotecario", "bank" => "Bancolombia" } ] }
      data = Ai::StatementExtractor.parse(raw, text: "Número de contrato: 73000123456")
      source = data[:sources].first
      assert_equal "73000123456", source[:identifier]
      assert_nil source[:card_last_four]
    end

    test "does not override a loan identifier already extracted" do
      raw = { "sources" => [ { "kind" => "loan", "name" => "Crédito", "bank" => "Bancolombia",
                               "identifier" => "111222333" } ] }
      data = Ai::StatementExtractor.parse(raw, text: "Número de contrato: 73000123456")
      assert_equal "111222333", data[:sources].first[:identifier]
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
