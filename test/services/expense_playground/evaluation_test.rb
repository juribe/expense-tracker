# frozen_string_literal: true

require "test_helper"

module ExpensePlayground
  class EvaluationTest < ActiveSupport::TestCase
    def candidate
      ExpenseCandidate.new(
        amount: 50_000,
        currency: "COP",
        category_id: 1,
        category_name: "Food",
        description: "Almuerzos",
        merchant: nil,
        date: Date.new(2026, 9, 9),
        confidence: 0.94,
        money_source_id: 7,
        money_source_name: "Nequi"
      )
    end

    test "all fields match" do
      result = Evaluation.call(
        candidate: candidate,
        expected: { amount: "50000", category: "food", description: "almuerzos", date: "2026-09-09" }
      )

      assert result[:ok?]
      assert_equal 4, result[:passed]
      assert_equal 4, result[:total]
      assert result[:checks].all? { |check| check[:passed] }
    end

    test "amount accepts Colombian shorthand expectations" do
      assert Evaluation.call(candidate: candidate, expected: { amount: "50 mil" })[:ok?]
      assert Evaluation.call(candidate: candidate, expected: { amount: "50k" })[:ok?]
      assert_not Evaluation.call(candidate: candidate, expected: { amount: 60_000 })[:ok?]
    end

    test "category and description comparisons are accent/case insensitive" do
      assert Evaluation.call(candidate: candidate, expected: { category: "FOOD" })[:ok?]
      assert Evaluation.call(candidate: candidate, expected: { description: "Almuerzos" })[:ok?]
      assert_not Evaluation.call(candidate: candidate, expected: { category: "transport" })[:ok?]
    end

    test "description passes on partial containment" do
      assert Evaluation.call(candidate: candidate, expected: { description: "almuerzo" })[:ok?]
    end

    test "merchant expectations use normalized containment" do
      assert_not Evaluation.call(candidate: candidate, expected: { merchant: "Éxito" })[:ok?]

      matching = candidate.tap { |c| c.merchant = "supermercado exito" }
      assert Evaluation.call(candidate: matching, expected: { merchant: "éxito" })[:ok?]
    end

    test "source expectations use normalized containment on the money source name" do
      assert Evaluation.call(candidate: candidate, expected: { source: "NEQUI" })[:ok?]
      assert Evaluation.call(candidate: candidate, expected: { source: "neq" })[:ok?]
      assert_not Evaluation.call(candidate: candidate, expected: { source: "bancolombia" })[:ok?]
      assert_not Evaluation.call(candidate: ExpenseCandidate.new(amount: 1, currency: "COP", category_name: "Food", date: Date.current),
                                 expected: { source: "nequi" })[:ok?]
    end

    test "blank expected fields are skipped and do not count" do
      result = Evaluation.call(candidate: candidate, expected: { category: "food", description: "" })
      assert_equal 1, result[:total]
      assert_equal 1, result[:passed]
    end

    test "no expectations yields an empty evaluation" do
      result = Evaluation.call(candidate: candidate, expected: {})
      assert_equal 0, result[:total]
      assert_not result[:ok?]
    end

    test "score reports partial correctness" do
      result = Evaluation.call(
        candidate: candidate,
        expected: { amount: "50000", category: "transport", description: "gasolina" }
      )
      assert_equal 1, result[:passed]
      assert_equal 3, result[:total]
      assert_not result[:ok?]
    end

    test "works from ActionController-style string params" do
      result = Evaluation.new(
        candidate: candidate,
        expected: ActionController::Parameters.new(
          expected: { "amount" => "50000", "category" => "food" }
        ).permit(expected: %i[amount category])[:expected]
      ).result

      assert result[:ok?]
    end
  end
end
