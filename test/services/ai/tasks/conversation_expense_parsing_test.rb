# frozen_string_literal: true

require "test_helper"

class Ai::Tasks::ConversationExpenseParsingTest < ActiveSupport::TestCase
  def task
    @task ||= Ai::Tasks::ConversationExpenseParsing.new
  end

  test "builds system and user messages with current date and categories" do
    categories = [ "Comida", "Transporte" ]
    messages = task.messages("Pagué 50 mil en gasolina", today: Date.new(2026, 9, 16), categories: categories)

    assert_equal "system", messages.first[:role]
    assert_includes messages.first[:content], "Fecha actual: 2026-09-16"
    assert_includes messages.first[:content], "Categorías permitidas: [Comida, Transporte]"
    assert_includes messages.first[:content], "original_text"

    assert_equal "user", messages.last[:role]
    assert_equal "Pagué 50 mil en gasolina", messages.last[:content]
  end

  test "parse returns data and per-expense confidence for a valid response" do
    content = {
      expenses: [
        { "original_text" => "50 mil", "amount" => 50_000, "confidence" => 0.3 },
        { "original_text" => "20 mil", "amount" => 20_000, "confidence" => 0.7 }
      ]
    }.to_json

    parsed = task.parse(content, "input", {})

    assert_equal 0.3, parsed[:confidence]
    assert_equal 50_000, parsed[:data].first["amount"]
  end

  test "parse uses 0.5 confidence when an entry omits it" do
    content = { expenses: [ { "original_text" => "50 mil", "amount" => 50_000 } ] }.to_json

    assert_equal 0.5, task.parse(content, "input", {})[:confidence]
  end

  test "parse removes the internal confidence key from the entries" do
    content = { expenses: [ { "original_text" => "50 mil", "amount" => 50_000, "confidence" => 0.9 } ] }.to_json

    refute_includes task.parse(content, "input", {})[:data].first.keys, "confidence"
  end

  test "parse strips whitespace from string values" do
    content = { expenses: [ { "original_text" => "  50 mil  ", "category" => " Transporte " } ] }.to_json

    entry = task.parse(content, "input", {})[:data].first

    assert_equal "50 mil", entry["original_text"]
    assert_equal "Transporte", entry["category"]
  end

  test "parse rejects non-JSON content" do
    assert_raises(Ai::Tasks::Base::InvalidResponse) { task.parse("not json", "input", {}) }
  end

  test "parse rejects a missing expenses array" do
    assert_raises(Ai::Tasks::Base::InvalidResponse) { task.parse("{ \"other\": [] }", "input", {}) }
  end
end
