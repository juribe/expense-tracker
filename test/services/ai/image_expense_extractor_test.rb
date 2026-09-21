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

    test "call succeeds through the strong-tier provider and records usage" do
      user = User.create!(name: "Vision User", email: "vision@example.com", password: "password123")
      payload = {
        ocr_text: "TOTAL 50.000",
        expenses: [ { amount: 50_000, merchant: "Restaurante", category: "restaurants", confidence: 0.95 } ]
      }.to_json
      strong = FakeAiProvider.new(responses: [ { content: payload, input_tokens: 30, output_tokens: 12 } ])

      result = nil
      stub_method(Ai::Providers, :strong, ->(*) { strong }) do
        with_env({ "MISTRAL_API_KEY" => "test-key" }) do
          result = Ai::ImageExpenseExtractor.new(
            image_data: "data:image/jpeg;base64,Zm9v",
            context_text: "almuerzo",
            user: user
          ).call
        end
      end

      assert result[:ok?], result[:error].inspect
      assert_equal "TOTAL 50.000", result.dig(:data, :ocr_text)
      assert_equal BigDecimal(50_000.to_s), result.dig(:data, :expenses, 0, :amount)

      row = AiRequest.where(task: "image_extraction").last
      assert_equal "strong_ai", row.strategy
      assert_equal "ok", row.status
      assert_equal 30, row.input_tokens
      # observability parity with the text pipeline: attributed to the user,
      # with the prompt recorded — but never the base64 image payload
      assert_equal user.id, row.user_id
      assert_in_delta 0.95, row.confidence, 0.001
      assert row.prompt.present?
      assert_match(/image attached/, row.prompt.to_s)
      assert_not row.prompt.to_s.include?("Zm9v")
      assert row.output.present?
    end

    test "call fails cleanly when the provider rejects the request" do
      strong = FakeAiProvider.new(responses: [ Ai::Provider::Error.new("AI HTTP 500") ])

      result = nil
      stub_method(Ai::Providers, :strong, ->(*) { strong }) do
        with_env({ "MISTRAL_API_KEY" => "test-key" }) { result = extractor.call }
      end

      refute result[:ok?]
      assert_match(/AI HTTP 500/, result[:error])
      assert_equal "error", AiRequest.where(task: "image_extraction").last.status
    end

    test "a truncated JSON payload is retried once with a corrective instruction and succeeds" do
      payload = { ocr_text: "TOTAL 50.000", expenses: [ { amount: 50_000, merchant: "Restaurante" } ] }.to_json
      strong = FakeAiProvider.new(responses: [ "{", { content: payload, input_tokens: 30, output_tokens: 12 } ])

      result = nil
      stub_method(Ai::Providers, :strong, ->(*) { strong }) do
        with_env({ "MISTRAL_API_KEY" => "test-key" }) { result = extractor.call }
      end

      assert result[:ok?], result[:error].inspect
      assert_equal 2, strong.calls.length
      assert_equal "ok", AiRequest.where(task: "image_extraction").last.status

      # the retry must change the prompt: temperature 0 would otherwise
      # reproduce the same broken output verbatim
      first_text = strong.calls.first.last[:content].first[:text]
      retry_text = strong.calls.last.last[:content].first[:text]
      assert_nil first_text
      assert_match(/previous response was invalid/, retry_text)
    end

    test "retries are exhausted into a clean parse failure with the raw output recorded" do
      strong = FakeAiProvider.new(responses: [ "{", "{ broken" ])

      result = nil
      stub_method(Ai::Providers, :strong, ->(*) { strong }) do
        with_env({ "MISTRAL_API_KEY" => "test-key" }) { result = extractor.call }
      end

      refute result[:ok?]
      assert_match(/invalid AI response/, result[:error])
      assert_equal 2, strong.calls.length

      row = AiRequest.where(task: "image_extraction").last
      assert_equal "error", row.status
      assert_equal "{ broken", row.output
    end
  end
end
