# frozen_string_literal: true

require "test_helper"

class Ai::Tasks::CategorySuggestionTest < ActiveSupport::TestCase
  def task
    @task ||= Ai::Tasks::CategorySuggestion.new
  end

  def input
    [
      { "index" => 0, "description" => "pago de ropa" },
      { "index" => 1, "description" => "arreglo de reloj" }
    ]
  end

  test "builds system and user messages from the pending items" do
    messages = task.messages(input, {})

    assert_equal "system", messages.first[:role]
    assert_includes messages.first[:content], "categoría general y reutilizable"
    assert_includes messages.first[:content], "Devuelve solo JSON válido"
    assert_includes messages.first[:content], "confidence"

    assert_equal "user", messages.last[:role]
    assert_equal input.to_json, messages.last[:content]
  end

  test "parse maps category suggestions by index" do
    content = [
      { "index" => 0, "category_suggestion" => "Ropa", "confidence" => 0.95 },
      { "index" => 1, "category_suggestion" => "Accesorios", "confidence" => 0.9 }
    ].to_json

    parsed = task.parse(content, input, {})

    assert_equal({ "0" => "Ropa", "1" => "Accesorios" }, parsed[:data])
    assert_in_delta 0.9, parsed[:confidence]
  end

  test "parse returns nil suggestion when the purpose is unclear" do
    content = [ { "index" => 0, "category_suggestion" => nil, "confidence" => 0.2 } ].to_json

    parsed = task.parse(content, input, {})

    assert_equal({ "0" => nil }, parsed[:data])
    assert_in_delta 0.2, parsed[:confidence]
  end

  test "parse defaults missing confidence to 0.5" do
    content = [ { "index" => 0, "category_suggestion" => "Ropa" } ].to_json

    parsed = task.parse(content, input, {})

    assert_equal({ "0" => "Ropa" }, parsed[:data])
    assert_in_delta 0.5, parsed[:confidence]
  end

  test "parse clamps confidence values outside 0..1" do
    content = [ { "index" => 0, "category_suggestion" => "Ropa", "confidence" => 1.5 } ].to_json

    parsed = task.parse(content, input, {})

    assert_in_delta 1.0, parsed[:confidence]
  end

  test "parse strips whitespace from suggestions" do
    content = [ { "index" => 0, "category_suggestion" => "  Ropa  ", "confidence" => 0.9 } ].to_json

    parsed = task.parse(content, input, {})

    assert_equal({ "0" => "Ropa" }, parsed[:data])
  end

  test "parse ignores malformed entries and unknown indices" do
    content = [
      "not an entry",
      { "index" => 0, "category_suggestion" => "Ropa", "confidence" => 0.9 },
      { "index" => 7, "category_suggestion" => "Ghost", "confidence" => 0.9 }
    ].to_json

    parsed = task.parse(content, input, {})

    assert_equal({ "0" => "Ropa" }, parsed[:data])
  end

  test "parse accepts a single suggestion object without an array wrapper" do
    content = { "index" => 0, "category_suggestion" => "Ropa", "confidence" => 0.9 }.to_json

    parsed = task.parse(content, input, {})

    assert_equal({ "0" => "Ropa" }, parsed[:data])
    assert_in_delta 0.9, parsed[:confidence]
  end

  test "parse rejects non-JSON content" do
    assert_raises(Ai::Tasks::Base::InvalidResponse) { task.parse("not json", input, {}) }
  end

  test "parse rejects a payload without an array of suggestions" do
    assert_raises(Ai::Tasks::Base::InvalidResponse) { task.parse({ "other" => [] }.to_json, input, {}) }
  end

  test "parse rejects an array with no usable entries" do
    assert_raises(Ai::Tasks::Base::InvalidResponse) { task.parse([ "junk" ].to_json, input, {}) }
  end
end
