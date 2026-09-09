# frozen_string_literal: true

require "test_helper"

module ExpensePlayground
  # Regression tests for money source detection in the playground pipeline:
  # text inputs detect through ExpenseParser, image inputs through the local
  # OCR text (parsed by ExpenseParser) or the user note in the vision
  # fallback.
  class MoneySourceDetectionTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "MS User", email: "ms-test@example.com", password: "password123")
      @category = Category.create!(name: "Restaurants", is_default: true, category_type: "expense")
      @nequi = MoneySource.create!(user: @user, name: "Nequi", kind: "wallet", starting_balance: 100_000)
      @bancolombia = MoneySource.create!(user: @user, name: "Ahorros", kind: "account",
                                         bank: "Bancolombia", starting_balance: 1_000_000)
      @saved_api_key = ENV.delete("MISTRAL_API_KEY")
    end

    teardown do
      ENV["MISTRAL_API_KEY"] = @saved_api_key
    end

    def stub_vision(expenses, ocr_text: "RECIBO")
      stub_method(Ai::ImageExpenseExtractor, :call, ->(**_kwargs) {
        { ok?: true, data: { ocr_text: ocr_text, expenses: expenses }, error: nil }
      }) { yield }
    end

    test "text pipeline detects money source by name" do
      result = ProcessingService.call(user: @user, input: Input.new(type: :text, text: "Me gasté 50 mil en almuerzo desde nequi"))

      assert result.ok?, "expected ok, got errors: #{result.errors.inspect}"
      assert_equal @nequi.id, result.candidate.money_source_id
      assert_equal @nequi.id, result.steps[:normalization][:money_source_id]
      assert_equal "Nequi", result.steps[:normalization][:money_source_name]
    end

    test "image pipeline detects money source from the user's note" do
      stub_method(Ocr::LocalReader, :call, nil) do
        stub_vision([ { amount: 25_000, currency: "COP", merchant: "Cafe", description: "Almuerzo",
                        category_name: "Restaurants", create_category: false,
                        transaction_date: Date.current.iso8601, confidence: 0.8 } ]) do
          result = ProcessingService.call(user: @user, input: Input.new(
            type: :image, image_data: "data:image/jpeg;base64,Zm9v", text: "pagué con bancolombia"
          ))

          assert result.ok?, "expected ok, got errors: #{result.errors.inspect}"
          assert_equal @bancolombia.id, result.candidate.money_source_id
          assert_equal "Ahorros", result.steps[:normalization][:money_source_name]
        end
      end
    end

    test "image pipeline detects money source in the local OCR text through the parser" do
      stub_method(Ocr::LocalReader, :call, "TOTAL 30.000\nPAGO POR NEQUI") do
        result = ProcessingService.call(user: @user, input: Input.new(
          type: :image, image_data: "data:image/jpeg;base64,Zm9v"
        ))

        assert result.ok?, "expected ok, got errors: #{result.errors.inspect}"
        assert_equal BigDecimal(30_000.to_s), result.candidate.amount
        assert_equal @nequi.id, result.candidate.money_source_id
        assert_equal "Nequi", result.steps[:normalization][:money_source_name]
      end
    end

    test "image pipeline leaves the source empty when nothing is mentioned" do
      stub_method(Ocr::LocalReader, :call, nil) do
        stub_vision([ { amount: 30_000, currency: "COP", merchant: "Tienda", description: "Compra",
                        category_name: "Groceries", create_category: false,
                        transaction_date: Date.current.iso8601, confidence: 0.8 } ]) do
          result = ProcessingService.call(user: @user, input: Input.new(
            type: :image, image_data: "data:image/jpeg;base64,Zm9v"
          ))

          assert result.ok?, "expected ok, got errors: #{result.errors.inspect}"
          assert_nil result.candidate.money_source_id
        end
      end
    end
  end
end
