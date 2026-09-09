# frozen_string_literal: true

require "test_helper"

module Ai
  class ImageExpenseExtractorTest < ActiveSupport::TestCase
    def extractor(context_text: nil, today: Date.current)
      Ai::ImageExpenseExtractor.new(
        image_data: "data:image/jpeg;base64,Zm9v",
        context_text: context_text,
        today: today
      )
    end

    def parse(raw, today = Date.current)
      extractor(today: today).send(:parse_response, raw)
    end

    test "normalizes the canonical receipt response" do
      data = parse(
        {
          "ocr_text" => "SUPERMERCADO ÉXITO\nTOTAL 87.500",
          "expenses" => [
            {
              "amount" => "87.500", "currency" => "COP", "merchant" => "Supermercado Éxito",
              "description" => "Compra supermercado", "category" => "groceries",
              "transaction_date" => "2026-09-01", "confidence" => 0.9
            }
          ]
        }
      )

      assert_equal "SUPERMERCADO ÉXITO\nTOTAL 87.500", data[:ocr_text]
      entry = data[:expenses].first
      assert_equal BigDecimal(87_500.to_s), entry[:amount]
      assert_equal "COP", entry[:currency]
      assert_equal "Supermercado Éxito", entry[:merchant]
      assert_equal "groceries", entry[:category_name]
      assert_equal Date.new(2026, 9, 1), Date.iso8601(entry[:transaction_date])
      assert_in_delta 0.9, entry[:confidence], 0.001
    end

    test "interprets comma decimals and defaults the date to today" do
      today = Date.new(2026, 9, 9)
      data = parse({ "ocr_text" => "", "expenses" => [ { "amount" => "8,5", "currency" => "usd" } ] }, today)

      entry = data[:expenses].first
      assert_equal BigDecimal("8.5"), entry[:amount]
      assert_equal "USD", entry[:currency]
      assert_equal today.iso8601, entry[:transaction_date]
      assert_equal 0.5, entry[:confidence]
      assert_nil entry[:merchant]
    end

    test "keeps an ocr-only response without expenses" do
      data = parse({ "ocr_text" => "ticket", "expenses" => [] })
      assert_equal "ticket", data[:ocr_text]
      assert_empty data[:expenses]
    end

    test "drops invalid entries" do
      data = parse(
        "expenses" => [
          { "amount" => 0, "merchant" => "No amount" },
          { "amount" => "n/a", "merchant" => "Bad amount" },
          { "amount" => 5_000, "merchant" => "Valid" }
        ]
      )
      assert_equal 1, data[:expenses].length
      assert_equal "Valid", data[:expenses].first[:merchant]
    end

    test "raises when the payload is unusable" do
      assert_raises(Ai::ImageExpenseExtractor::ExtractionError) { parse({}) }
      assert_raises(Ai::ImageExpenseExtractor::ExtractionError) { parse({ "ocr_text" => "x" }) }
    end

    test "call fails cleanly without an API key configured" do
      result = with_env({ "MISTRAL_API_KEY" => nil }) do
        extractor.call
      end

      assert_not result[:ok?]
      assert_match(/not configured/, result[:error])
    end

    test "call succeeds with a stubbed HTTP response" do
      body = {
        choices: [ { message: { content: {
          ocr_text: "TOTAL 50.000",
          expenses: [ { amount: 50_000, merchant: "Restaurante", category: "restaurants", confidence: 0.95 } ]
        }.to_json } } ]
      }.to_json
      fake_response = Struct.new(:code, :body).new("200", body)

      extractor = Ai::ImageExpenseExtractor.new(image_data: "data:image/jpeg;base64,Zm9v")
      stub_method(extractor, :perform_request, ->(_http, _request) { fake_response }) do
        @result = extractor.call
      end
      result = @result

      assert result[:ok?], result[:error].inspect
      assert_equal "TOTAL 50.000", result.dig(:data, :ocr_text)
      assert_equal BigDecimal(50_000.to_s), result.dig(:data, :expenses, 0, :amount)
    end

    test "perform_request retries a 429 then returns a 200" do
      fake = Struct.new(:code)
      calls = []
      sequence = [ fake.new("429"), fake.new("429"), fake.new("200") ]

      result = extractor.send(:retry_with_backoff) do
        calls << sequence.shift
        calls.last
      end

      assert_equal "200", result.code
      assert_equal 3, calls.size
    end

    test "perform_request gives up on persistent 429 after retrying" do
      fake = Struct.new(:code)
      calls = []
      sequence = [ fake.new("429"), fake.new("429"), fake.new("429") ]

      error = assert_raises(Ai::ImageExpenseExtractor::ExtractionError) do
        extractor.send(:retry_with_backoff) do
          calls << sequence.shift
          calls.last
        end
      end

      assert_match(/AI HTTP 429/, error.message)
      assert_equal 3, calls.size
    end
  end
end
