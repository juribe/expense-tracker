# frozen_string_literal: true

require "test_helper"

# Deterministic first pass of the expense resolver: verifies the adapter maps
# heuristic entries into the Ai::Tasks::ParsedExpense shape the
# resolver pipeline consumes, keeping the matched text slice as original_text.
class ExpenseResolverHeuristicParserTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 9, 16)

  setup do
    @categories = [
      Category.new(name: "Restaurants", category_type: "expense"),
      Category.new(name: "Parking", category_type: "expense")
    ]
  end

  def parse(text, today: TODAY)
    ExpenseResolver::HeuristicParser.call(text: text, categories: @categories, today: today)
  end

  test "maps a heuristic entry into the AI entry shape" do
    entries = parse("gasté 50 mil en almuerzo")

    assert_equal 1, entries.length
    entry = entries.first
    assert_kind_of Ai::Tasks::ParsedExpense, entry
    assert_equal 50_000, entry.amount.to_i
    assert_equal TODAY, entry.date
    assert_equal "Restaurants", entry.category
    assert_equal "Almuerzo", entry.description
    assert entry.confidence >= 0.9
  end

  test "keeps the matched text slice as original_text" do
    entries = parse("gasté 50 mil en almuerzo y 20 mil en parqueadero")

    assert_equal 2, entries.length
    original_texts = entries.map(&:original_text)
    assert_includes original_texts[0], "50 mil"
    assert_includes original_texts[1], "20 mil"
    refute_includes original_texts[0], "20 mil"
    refute_includes original_texts[1], "50 mil"
  end

  test "resolves relative dates from the text" do
    entries = parse("ayer gasté 50 mil en almuerzo")

    assert_equal TODAY - 1, entries.first.date
    assert_includes entries.first.original_text, "ayer"
  end

  test "returns an empty list when no amount can be scanned" do
    assert_empty parse("pagué algo raro con plata")
  end
end
