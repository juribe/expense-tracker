require "test_helper"

module ExpenseResolver
  class AmountResultTest < ActiveSupport::TestCase
    test "keeps a model quantity total the itemized text corroborates" do
      result = AmountResult.call(amount: 25_500, text: "Tres cafés de 8.500 cada uno")

      assert_equal 25_500, result.amount
      assert_nil result.suggested_amount
    end

    test "still overrides a guessed amount when the text has a single confident read" do
      result = AmountResult.call(amount: 30_000, text: "gasté 50 mil en almuerzo")

      assert_equal 50_000, result.amount
    end

    test "keeps a merged total the itemized amounts corroborate" do
      result = AmountResult.call(amount: 82_000, text: "Almuerzo 72.000 más 10.000 de propina")

      assert_equal 82_000, result.amount
    end

    test "the overridden unit price still flags the quantity mismatch" do
      # The model kept the unit price: the heuristic read matches it, and the
      # downstream SumValidator flags the missing quantity multiplication.
      result = AmountResult.call(amount: 8_500, text: "Tres cafés de 8.500 cada uno")

      assert_equal 8_500, result.amount
    end
  end
end
