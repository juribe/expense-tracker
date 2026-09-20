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

  # === Ported from the old ExpenseParser suite ==============================

  test "understands Colombian currency expressions" do
    assert_equal 50_000, parse("50 mil en almuerzo").first.amount.to_i
    assert_equal 50_000, parse("Me gasté 50 lucas en almuerzo").first.amount.to_i
    assert_equal 80_000, parse("Gasté 80k en gasolina").first.amount.to_i
    assert_equal 50_000, parse("pagué 50.000 pesos en el mercado").first.amount.to_i
    assert_equal 500_000, parse("medio millón en arriendo").first.amount.to_i
    assert_equal 50_000, parse("cincuenta mil en cine").first.amount.to_i
    assert_equal 250_000, parse("un cuarto de millón en ropa").first.amount.to_i
  end

  test "detects relative dates: hoy, ayer and anteayer" do
    assert_equal TODAY, parse("Hoy gasté 30 mil en almuerzo").first.date
    assert_equal TODAY - 1, parse("Ayer gasté 100 mil en gasolina").first.date
    assert_equal TODAY - 2, parse("anteayer gasté 5 mil en cafe").first.date
  end

  test "anteayer takes precedence over ayer" do
    assert_equal TODAY - 2, parse("anteayer gasté 5 mil en cafe").first.date
  end

  test "resolves weekdays to the most recent past occurrence" do
    # 2026-09-16 is a Wednesday, so the most recent lunes is the 14th.
    assert_equal Date.new(2026, 9, 14), parse("El lunes gasté 50 mil en mercado").first.date
  end

  test "each expense keeps its own date in mixed messages" do
    entries = parse("Ayer gasté 100 mil en gasolina y hoy gaste 30 mil en almuerzo")

    assert_equal [ TODAY - 1, TODAY ], entries.map(&:date)
  end

  test "defaults to today when no date expression is present" do
    assert_equal TODAY, parse("50 mil en almuerzo").first.date
  end

  test "maps descriptions to existing user categories" do
    gasoline = Category.new(name: "Gasoline", category_type: "expense")
    @categories << gasoline

    entries = parse("Gasté 80 mil en gasolina y 25 mil en parqueadero")

    assert_equal "Gasoline", entries[0].category
    assert_equal "Parking", entries[1].category
  end

  test "suggests a canonical category when a keyword group matches but no category exists" do
    entries = parse("Gasté 30 mil en la veterinaria del perro")

    entry = entries.first
    assert_equal "Pet Care", entry.category
    assert_operator entry.confidence, :<, Ai::Tasks::ParsedExpense::LOW_CONFIDENCE_THRESHOLD
  end
end
