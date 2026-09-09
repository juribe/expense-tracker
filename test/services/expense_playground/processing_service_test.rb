# frozen_string_literal: true

require "test_helper"

module ExpensePlayground
  class ProcessingServiceTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Playground User", email: "playground@example.com", password: "password123")
      @restaurants = Category.create!(name: "Restaurants", is_default: true, category_type: "expense")
      @saved_api_key = ENV.delete("MISTRAL_API_KEY")
    end

    teardown do
      ENV["MISTRAL_API_KEY"] = @saved_api_key
    end

    def process(input)
      ProcessingService.call(user: @user, input: input)
    end

    test "text input produces a normalized candidate without persisting anything" do
      assert_no_difference -> { Expense.count } do
        result = process(Input.new(type: :text, text: "Me gasté 50mil en almuerzos"))
        assert result.ok?
        assert_equal "heuristic", result.engine # AI key is unset, so the parser falls back

        candidate = result.candidate
        assert_equal BigDecimal(50_000.to_s), candidate.amount
        assert_equal "COP", candidate.currency
        assert_equal @restaurants.id, candidate.category_id
        assert_equal "almuerzos", candidate.description.downcase
        assert_equal Date.current, candidate.date
        assert candidate.confidence.present?
      end
    end

    test "text pipeline records every stage for the debug view" do
      result = process(Input.new(type: :text, text: "Netflix 29.900"))

      assert_equal "text", result.steps[:input][:type]
      assert_equal false, result.steps[:ocr][:applicable]
      assert result.steps[:extraction][:engine].present?
      assert result.steps[:extraction][:raw].is_a?(Array)
      assert_equal BigDecimal("29900"), result.steps[:normalization][:amount]
      assert_equal "COP", result.steps[:normalization][:currency]
      assert result.steps[:validation][:valid]
      assert result.duration_ms >= 0
    end

    test "text input with no detectable amount reports a clear error" do
      result = process(Input.new(type: :text, text: "hola que tal"))

      assert_not result.ok?
      assert_nil result.candidate
      assert result.errors.any? { |error| error.include?("Could not extract an expense") }
      refute result.steps[:validation]&.dig(:valid)
    end

    # Image tests stub the local OCR reader to read nothing, forcing the
    # vision-model fallback that those tests exercise.
    def stub_vision_fallback(extractor_result)
      stub_method(Ocr::LocalReader, :call, nil) do
        stub_method(Ai::ImageExpenseExtractor, :call, ->(**_kwargs) { extractor_result }) { yield }
      end
    end

    test "image input runs OCR + vision extraction and normalizes the result" do
      extractor_result = {
        ok?: true,
        data: {
          ocr_text: "SUPERMERCADO ÉXITO\nTOTAL 87.500",
          expenses: [ {
            amount: BigDecimal(87_500.to_s), currency: "COP", merchant: "Supermercado Éxito",
            description: "Compra supermercado", category_name: "groceries",
            create_category: false, transaction_date: Date.current.iso8601, confidence: 0.9
          } ]
        },
        error: nil
      }
      stub_vision_fallback(extractor_result) do
        result = process(Input.new(type: :image, image_data: "data:image/jpeg;base64,Zm9v"))
        assert result.ok?
        assert_equal "vision", result.engine

        assert result.steps[:ocr][:applicable]
        assert_equal "mistral-vision", result.steps[:ocr][:engine]
        assert_match(/SUPERMERCADO/, result.steps[:ocr][:text])
        assert_equal "vision", result.steps[:extraction][:engine]

        candidate = result.candidate
        assert_equal BigDecimal(87_500.to_s), candidate.amount
        assert_equal "Supermercado Éxito", candidate.merchant
        assert_equal "COP", candidate.currency
        assert candidate.date.present?
      end
    end

    test "image with unknown category keeps the extracted name and warns" do
      extractor_result = {
        ok?: true,
        data: {
          ocr_text: "TIENDA",
          expenses: [ { amount: 10_000, currency: "COP", merchant: "Tienda",
                        description: nil, category_name: "mascotas", create_category: false,
                        transaction_date: Date.current.iso8601, confidence: 0.6 } ]
        },
        error: nil
      }
      stub_vision_fallback(extractor_result) do
        result = process(Input.new(type: :image, image_data: "data:image/jpeg;base64,Zm9v"))
        assert result.candidate.category_id.nil?
        assert_equal "mascotas", result.candidate.category_name
        assert result.warnings.any? { |warning| warning.include?("mascotas") }
      end
    end

    test "image with a category matching the user's categories resolves the id" do
      extractor_result = {
        ok?: true,
        data: {
          ocr_text: "MENU",
          expenses: [ { amount: 25_000, currency: "COP", merchant: nil,
                        description: "Almuerzo", category_name: "restaurants", create_category: false,
                        transaction_date: Date.current.iso8601, confidence: 0.8 } ]
        },
        error: nil
      }
      stub_vision_fallback(extractor_result) do
        result = process(Input.new(type: :image, image_data: "data:image/jpeg;base64,Zm9v"))
        assert_equal @restaurants.id, result.candidate.category_id
        assert_equal "Restaurants", result.candidate.category_name
      end
    end

    test "failed vision extraction surfaces a friendly error with pipeline details" do
      stub_vision_fallback({ ok?: false, data: nil, error: "AI HTTP 500" }) do
        result = process(Input.new(type: :image, image_data: "data:image/jpeg;base64,Zm9v"))

        assert_not result.ok?
        assert_nil result.candidate
        assert result.errors.any? { |error| error.include?("extraction service") }
        assert_equal "vision", result.steps[:extraction][:engine]
      end
    end

    test "local OCR text is parsed like a text input without sending the image" do
      stub_method(Ocr::LocalReader, :call, "Almuerzo con el equipo 85 mil") do
        result = process(Input.new(type: :image, image_data: "data:image/jpeg;base64,Zm9v"))
        assert result.ok?
        assert_equal "tesseract", result.steps[:ocr][:engine]
        assert_equal "heuristic", result.engine
        assert_equal BigDecimal(85_000.to_s), result.candidate.amount
      end
    end

    test "text + image input parses the note together with the local OCR text" do
      stub_method(Ocr::LocalReader, :call, "TOTAL 87.500") do
        result = process(Input.new(type: :text_image, text: "pagado con nequi",
                                   image_data: "data:image/jpeg;base64,Zm9v"))
        assert result.ok?
        assert_equal "tesseract", result.steps[:ocr][:engine]
        assert_equal BigDecimal(87_500.to_s), result.candidate.amount
      end
    end

    test "vision OCR still runs for text + image input and uses the text as context" do
      seen = {}
      stub_method(Ocr::LocalReader, :call, nil) do
        stub_method(Ai::ImageExpenseExtractor, :call, ->(**kwargs) {
          seen.merge!(kwargs)
          { ok?: true, data: { ocr_text: "RECIBO",
                               expenses: [ { amount: 15_000, currency: "COP", merchant: "Cafe",
                                             description: "Cafe", category_name: "Restaurants",
                                             create_category: false, transaction_date: Date.current.iso8601,
                                             confidence: 0.8 } ] },
            error: nil }
        }) do
          result = process(Input.new(type: :text_image, text: "Este fue el recibo del almuerzo",
                                     image_data: "data:image/jpeg;base64,Zm9v"))
          assert result.ok?
          assert_equal "Este fue el recibo del almuerzo", seen[:context_text]
          assert_equal @restaurants.id, result.candidate.category_id
        end
      end
    end

    test "invalid inputs never reach extraction" do
      result = process(Input.new(type: :text, text: ""))
      assert_not result.ok?
      assert_nil result.candidate
      assert result.steps[:input].present?
      assert result.errors.any?

      result = process(Input.new(type: :image, image_data: "data:text/html;base64,PGI+"))
      assert_not result.ok?
      assert result.errors.any? { |error| error.include?("Unsupported image format") }
    end

    test "processing never creates a real expense" do
      stub_method(Ocr::LocalReader, :call, nil) do
        stub_method(Ai::ImageExpenseExtractor, :call,
          ->(**_kwargs) { { ok?: false, data: nil, error: "AI HTTP 500" } }) do
          assert_no_difference -> { Expense.count } do
            process(Input.new(type: :image, image_data: "data:image/jpeg;base64,Zm9v"))
            process(Input.new(type: :text, text: "Compré gasolina por 120.000"))
          end
        end
      end
    end
  end
end
