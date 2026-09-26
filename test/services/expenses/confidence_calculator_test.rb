# frozen_string_literal: true

require "test_helper"

module Expenses
  class ConfidenceCalculatorTest < ActiveSupport::TestCase
    setup do
      @today = Date.new(2026, 9, 19)
      @categories = [ "Restaurants", "Transporte", "Mercado" ]
    end

    def expense(original_text: "gasté 50 mil en almuerzos", amount: 50_000,
                date: @today - 1, description: "almuerzos", category: "Restaurants")
      Ai::Tasks::ParsedExpense.new(
        original_text: original_text, amount: amount, date: date&.iso8601,
        description: description, category: category, money_source_hint: nil,
        confidence: nil
      )
    end

    def calculate(expense_record, input: "gasté 50 mil en almuerzos ayer")
      ConfidenceCalculator.call(
        expense: expense_record, input: input,
        categories: @categories, today: @today
      )
    end

    test "high confidence: every signal verified against the input" do
      result = calculate(expense)

      assert_equal 1.0, result.score
      assert_includes result.reasons, "original text matches a portion of the input (+0.1)"
      assert_includes result.reasons, "amount 50000 present and valid (+0.3)"
      assert_includes result.reasons, "amount 50000 explicitly found in original text (+0.15)"
      assert_includes result.reasons, "date #{@today - 1} present and valid (+0.1)"
      assert_includes result.reasons, "date resolved from the original text (explicit or relative) (+0.1)"
      assert_includes result.reasons, "category \"Restaurants\" is one of the available categories (+0.1)"
      assert_equal({ score: 1.0, reasons: result.reasons }, result.to_h)
    end

    test "nil category does not penalize the score" do
      result = calculate(
        expense(original_text: nil, amount: 30_000, date: @today,
                description: "cena", category: nil),
        input: "pagué 30 mil en cena"
      )

      # amount (0.30) + amount found in the input (0.15) + date present (0.10)
      # + description (0.15); category is nil so 0.0 (no penalty).
      # original_text is missing and date is not derivable from the text.
      assert_equal 0.70, result.score
      assert result.reasons.any? { |reason| reason.include?("category missing") }
      assert result.reasons.none? { |reason| reason.include?("half credit") }
    end

    test "incorrect category guess receives no credit" do
      result = calculate(
        expense(original_text: nil, amount: 30_000, date: @today,
                description: "cena", category: "Voladores"),
        input: "pagué 30 mil en cena"
      )

      # amount (0.30) + amount in text (0.15) + date present (0.10)
      # + description (0.15); category "Voladores" is not in available
      # categories, so 0.0 (no half credit for unverifiable guesses).
      assert_equal 0.70, result.score
      assert result.reasons.any? { |reason| reason.include?("not among the available categories") }
      assert result.reasons.none? { |reason| reason.include?("half credit") }
    end

    test "medium confidence when the amount was inferred instead of extracted" do
      result = calculate(
        expense(original_text: "pagué en el mercado el sábado", amount: 80_000,
                date: @today - 6, description: "mercado", category: "Mercado"),
        input: "pagué en el mercado el sábado"
      )

      # text match (0.10) + amount (0.30) + date present (0.10) + description
      # (0.15) + category (0.10); the amount is NOT in the text and the date
      # is not in the text.
      assert_equal 0.75, result.score
      assert result.reasons.any? { |reason| reason.include?("not found in the original text") }
      assert result.reasons.any? { |reason| reason.include?("not derivable") }
    end

    test "low confidence when almost nothing can be verified" do
      result = calculate(
        expense(original_text: nil, amount: nil, date: nil,
                description: "", category: nil),
        input: "no se"
      )

      assert_equal 0.0, result.score
      assert_equal 6, result.reasons.length
      assert result.reasons.all? { |reason| reason.include?("(+0.00") }
    end

    test "future dates take a fixed penalty" do
      result = calculate(expense(date: @today + 5), input: "gasté 50 mil en almuerzos el 24 de septiembre")

      # All signals except date-in-text fire (0.90); the future date takes -0.10.
      assert_equal 0.80, result.score
      assert result.reasons.any? { |reason| reason.include?("date is in the future") }
    end

    test "a hallucinated original_text that does not match the input gets partial credit" do
      result = calculate(expense(original_text: "compré algo totalmente distinto 50 mil"))

      assert_equal 0.95, result.score
      assert result.reasons.any? { |reason| reason.include?("half credit") }
    end

    test "legitimately optional fields never penalize the score" do
      # No merchant/money-source fields in the parser output — the calculator
      # must not invent reasons about them.
      result = calculate(expense)

      assert result.reasons.none? { |reason| reason.include?("merchant") }
      assert result.reasons.none? { |reason| reason.include?("money source") }
    end
  end
end
