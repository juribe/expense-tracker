# frozen_string_literal: true

require "test_helper"

module Ai
  class TransactionExtractorTest < ActiveSupport::TestCase
    def extractor
      @extractor ||= Ai::TransactionExtractor.new
    end

    def parse(raw, today = Date.current)
      Ai::TransactionExtractor.parse(raw, today: today)
    end

    test "normalizes the canonical purchase example" do
      data = parse(
        {
          "transactions" => [
            {
              "type" => "expense", "amount" => 48_500, "currency" => "COP",
              "merchant" => "Restaurante XYZ", "category" => "restaurants",
              "occurred_at" => "2026-08-23T14:30:00", "confidence" => 0.98,
              "card_last_four" => "1234"
            }
          ],
          "should_ignore" => false, "reason": nil
        }.deep_stringify_keys
      )

      transaction = data[:transactions].first
      assert_equal "expense", transaction[:type]
      assert_equal BigDecimal(48_500.to_s), transaction[:amount]
      assert_equal "COP", transaction[:currency]
      assert_equal "Restaurante XYZ", transaction[:merchant]
      assert_equal "restaurants", transaction[:category]
      assert_equal "1234", transaction[:card_last_four]
      assert_in_delta 0.98, transaction[:confidence], 0.001
      assert_equal false, data[:should_ignore]
    end

    test "keeps multiple transactions in one email" do
      data = parse(
        "transactions" => [
          { "type" => "expense", "amount" => 1000, "merchant" => "A" },
          { "type" => "expense", "amount" => 2000, "merchant" => "B" }
        ]
      )
      assert_equal 2, data[:transactions].size
    end

    test "maps synonyms to the expense type and defaults currency to COP" do
      data = parse("transactions" => [ { "type" => "compra", "amount" => "48.500", "merchant" => "Tienda" } ])
      assert_equal "expense", data[:transactions].first[:type]
      assert_equal BigDecimal(48_500.to_s), data[:transactions].first[:amount]
      assert_equal "COP", data[:transactions].first[:currency]
    end

    test "falls back gracefully on missing optional fields" do
      today = Date.new(2026, 8, 23)
      data = parse({ "transactions" => [ { "type" => "purchase", "amount" => 5000, "merchant" => "Cafe" } ] }, today)

      transaction = data[:transactions].first
      assert_equal "others", transaction[:category]
      assert_equal 0.5, transaction[:confidence]
      assert_nil transaction[:card_last_four]
      assert_match(/\A\d{4}-\d{2}-\d{2}T/, transaction[:occurred_at])
    end

    test "raises when transactions are missing or invalid" do
      assert_raises(Ai::TransactionExtractor::ExtractionError) { parse({}) }
      assert_raises(Ai::TransactionExtractor::ExtractionError) do
        parse("transactions" => [ { "amount" => 100, "merchant" => "" } ])
      end
      assert_raises(Ai::TransactionExtractor::ExtractionError) do
        parse("transactions" => [])
      end
    end

    test "call fails cleanly without an API key configured" do
      result = with_env({ "MISTRAL_API_KEY" => nil }) do
        extractor.call(subject: "Compra", body: "$10 en tienda")
      end

      assert_not result[:ok?]
      assert_match(/not configured/, result[:error])
    end

    test "perform_request retries a 429 then returns a 200" do
      fake = Struct.new(:code)
      calls = []
      response_sequence = [ fake.new("429"), fake.new("429"), fake.new("200") ]

      result = extractor.send(:retry_with_backoff) do
        calls << response_sequence.shift
        calls.last
      end

      assert_equal "200", result.code
      assert_equal 3, calls.size
    end

    test "perform_request gives up on persistent 429 after retrying" do
      fake = Struct.new(:code)
      calls = []
      response_sequence = [ fake.new("429"), fake.new("429"), fake.new("429") ]

      error = assert_raises(Ai::TransactionExtractor::ExtractionError) do
        extractor.send(:retry_with_backoff) do
          calls << response_sequence.shift
          calls.last
        end
      end

      assert_match(/AI HTTP 429/, error.message)
      assert_equal 3, calls.size
    end
  end
end
