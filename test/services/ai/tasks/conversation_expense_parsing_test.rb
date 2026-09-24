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
    assert_includes messages.first[:content], "Today: 2026-09-16"
    assert_includes messages.first[:content], "Available categories: [Comida, Transporte]"
    assert_includes messages.first[:content], "original_text"

    assert_equal "user", messages.last[:role]
    assert_equal "Pagué 50 mil en gasolina", messages.last[:content]
  end

  test "parse returns ParsedExpense entries and a pipeline-derived confidence" do
    content = {
      expenses: [
        { "original_text" => "50 mil", "amount" => 50_000, "confidence" => 0.3 },
        { "original_text" => "20 mil", "amount" => 20_000, "confidence" => 0.7 }
      ]
    }.to_json

    parsed = task.parse(content, "input", {})

    assert_kind_of Float, parsed[:confidence]
    assert_kind_of Ai::Tasks::ParsedExpense, parsed[:data].first
    assert_equal 50_000, parsed[:data].first.amount
  end

  test "parse derives confidence from pipeline signals instead of the model value" do
    content = { expenses: [ { "original_text" => "50 mil", "amount" => 50_000, "confidence" => 0.9 } ] }.to_json

    parsed = task.parse(content, "input", {})

    refute_equal 0.9, parsed[:data].first.confidence
    assert_equal parsed[:data].map(&:confidence).min, parsed[:confidence]
  end

  test "parse strips whitespace from string values" do
    content = { expenses: [ { "original_text" => "  50 mil  ", "category" => " Transporte " } ] }.to_json

    entry = task.parse(content, "input", {})[:data].first

    assert_equal "50 mil", entry.original_text
    assert_equal "Transporte", entry.category
  end

  test "parse rejects non-JSON content" do
    assert_raises(Ai::Tasks::Base::InvalidResponse) { task.parse("not json", "input", {}) }
  end

  test "parse rejects a missing expenses array" do
    assert_raises(Ai::Tasks::Base::InvalidResponse) { task.parse("{ \"other\": [] }", "input", {}) }
  end

  test "parse carries category_suggestion from AI entry" do
    content = {
      expenses: [
        { "original_text" => "comida para perro", "amount" => 80_000, "category" => nil, "category_suggestion" => "Mascotas" }
      ]
    }.to_json

    entry = task.parse(content, "input", {})[:data].first

    assert_nil entry.category
    assert_equal "Mascotas", entry.category_suggestion
  end

  test "parse with both category and category_suggestion uses category" do
    content = {
      expenses: [
        { "original_text" => "gasolina", "amount" => 50_000, "category" => "Transporte", "category_suggestion" => "Mascotas" }
      ]
    }.to_json

    entry = task.parse(content, "input", {})[:data].first

    assert_equal "Transporte", entry.category
    assert_equal "Mascotas", entry.category_suggestion
  end

  test "parse with both null returns nil category_suggestion" do
    content = {
      expenses: [
        { "original_text" => "le transferí a Juan", "amount" => 50_000, "category" => nil, "category_suggestion" => nil }
      ]
    }.to_json

    entry = task.parse(content, "input", {})[:data].first

    assert_nil entry.category
    assert_nil entry.category_suggestion
  end
end
