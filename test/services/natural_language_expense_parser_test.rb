# frozen_string_literal: true

require "test_helper"

# Single-AI-call natural-language expense parsing. AI providers are faked
# through Ai::Providers.strong; no network calls are made. The parser returns
# the raw entries the model produced; normalization lives in
# ExpenseCandidateProcessor.
class NaturalLanguageExpenseParserTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 9, 16)

  setup do
    @user = User.create!(name: "Parser User", email: "parser@example.com", password: "password123")
  end

  def parse(text, user: nil, categories: nil, current_date: TODAY, responses: [])
    provider = FakeAiProvider.new(responses: responses)
    result = nil
    stub_method(Ai::Providers, :strong, ->(*) { provider }) do
      result = NaturalLanguageExpenseParser.call(text: text, current_date: current_date, user: user, categories: categories)
    end
    [ result, provider ]
  end

  def json_response(entries)
    {
      content: { expenses: entries }.to_json,
      input_tokens: 20,
      output_tokens: 8
    }
  end

  test "parses a single expense" do
    result, = parse(
      "Pagué 50 mil de gasolina",
      responses: [ json_response([ {
        "original_text" => "Pagué 50 mil de gasolina", "amount" => 50_000,
        "date" => "2026-09-16", "description" => "gasolina", "category" => "Transporte",
        "money_source_hint" => nil
      } ]) ]
    )

    assert result.success?
    assert_equal 1, result.result.length
    assert_equal "Pagué 50 mil de gasolina", result.result.first["original_text"]
    assert_equal 50_000, result.result.first["amount"]
  end

  test "splits multiple expenses into separate entries" do
    result, = parse(
      "Pagué 50 mil de gasolina y 80 mil en comida",
      responses: [ json_response([
        { "original_text" => "Pagué 50 mil de gasolina", "amount" => 50_000,
          "date" => "2026-09-16", "description" => "gasolina", "category" => "Transporte",
          "money_source_hint" => nil },
        { "original_text" => "80 mil en comida", "amount" => 80_000,
          "date" => "2026-09-16", "description" => "comida", "category" => "Comida",
          "money_source_hint" => nil }
      ]) ]
    )

    assert result.success?
    assert_equal 2, result.result.length
    assert_equal [ "Pagué 50 mil de gasolina", "80 mil en comida" ],
                 result.result.map { |expense| expense["original_text"] }
  end

  test "preserves shared context once per expense" do
    result, = parse(
      "Ayer compré mercado por 180 mil, gasolina por 50 mil y cené por 80 mil.",
      responses: [ json_response([
        { "original_text" => "Ayer compré mercado por 180 mil", "amount" => 180_000,
          "date" => "2026-09-15", "description" => "mercado", "category" => "Compras",
          "money_source_hint" => nil },
        { "original_text" => "gasolina por 50 mil", "amount" => 50_000,
          "date" => "2026-09-15", "description" => "gasolina", "category" => "Transporte",
          "money_source_hint" => nil },
        { "original_text" => "cené por 80 mil", "amount" => 80_000,
          "date" => "2026-09-15", "description" => "cena", "category" => "Comida",
          "money_source_hint" => nil }
      ]) ]
    )

    assert result.success?
    assert_equal 3, result.result.length
    assert_equal [ "2026-09-15" ] * 3, result.result.map { |expense| expense["date"] }
  end

  test "captures the money source hint without resolving it" do
    result, = parse(
      "Ayer gasté 50 mil en gasolina con la clásica",
      responses: [ json_response([ {
        "original_text" => "Ayer gasté 50 mil en gasolina con la clásica", "amount" => 50_000,
        "date" => "2026-09-15", "description" => "gasolina", "category" => "Transporte",
        "money_source_hint" => "la clásica"
      } ]) ]
    )

    assert result.success?
    assert_equal "la clásica", result.result.first["money_source_hint"]
  end

  test "passes the current date to the model for relative date resolution" do
    result, provider = parse(
      "gasté 10 mil hoy, 20 mil ayer y 30 mil anteayer",
      current_date: TODAY,
      responses: [ json_response([ {
        "original_text" => "gasté 10 mil hoy", "amount" => 10_000, "date" => "2026-09-16",
        "description" => "hoy", "category" => "Otros", "money_source_hint" => nil
      } ]) ]
    )

    assert result.success?
    assert_equal [ "2026-09-16" ], result.result.map { |expense| expense["date"] }

    system_prompt = provider.calls.first.first[:content]
    assert_includes system_prompt, "Current date: 2026-09-16"
  end

  test "includes one of the allowed categories for every expense" do
    result, = parse(
      "compré 40 mil en restaurante y 25 mil en el cine",
      responses: [ json_response([
        { "original_text" => "compré 40 mil en restaurante", "amount" => 40_000,
          "date" => "2026-09-16", "description" => "restaurante", "category" => "Comida",
          "money_source_hint" => nil },
        { "original_text" => "25 mil en el cine", "amount" => 25_000,
          "date" => "2026-09-16", "description" => "cine", "category" => "Entretenimiento",
          "money_source_hint" => nil }
      ]) ]
    )

    assert result.success?
    assert_equal %w[Comida Entretenimiento], result.result.map { |expense| expense["category"] }
  end

  test "uses the user's expense categories when a user is provided" do
    Category.create!(name: "Hogar", category_type: "expense", user: @user)

    result, provider = parse(
      "pagué 30 mil en servicios",
      user: @user,
      responses: [ json_response([ {
        "original_text" => "pagué 30 mil en servicios", "amount" => 30_000,
        "date" => "2026-09-16", "description" => "servicios", "category" => "Hogar",
        "money_source_hint" => nil
      } ]) ]
    )

    assert result.success?
    assert_equal "Hogar", result.result.first["category"]

    system_prompt = provider.calls.first.first[:content]
    assert_includes system_prompt, "Hogar"
    refute_includes system_prompt, NaturalLanguageExpenseParser::DEFAULT_CATEGORIES.first
  end

  test "honors explicitly passed categories over user and default categories" do
    explicit = [ Category.new(name: "Antojos"), "Hogar" ]

    result, provider = parse(
      "pagué 30 mil en antojos",
      user: @user,
      categories: explicit,
      responses: [ json_response([ {
        "original_text" => "pagué 30 mil en antojos", "amount" => 30_000,
        "date" => "2026-09-16", "description" => "antojo", "category" => "Antojos",
        "money_source_hint" => nil
      } ]) ]
    )

    assert result.success?
    assert_equal "Antojos", result.result.first["category"]

    system_prompt = provider.calls.first.first[:content]
    assert_includes system_prompt, "Allowed categories: [Antojos, Hogar]"
  end

  test "returns the raw model entries without normalization" do
    result, = parse(
      "50.000 en almuerzo",
      responses: [ json_response([
        { "original_text" => "50.000 en almuerzo", "amount" => "50.000",
          "date" => "2026-09-16", "description" => "almuerzo", "category" => "Comida",
          "money_source_hint" => nil }
      ]) ]
    )

    assert result.success?
    assert_equal "50.000", result.result.first["amount"]
  end

  test "returns a controlled failure when the input is empty" do
    result, = parse("")

    assert result.failure?
    assert_equal [ "Text is empty." ], result.errors
  end

  test "returns a controlled failure when the AI response is invalid" do
    result, = parse(
      "conseguí esto raro",
      responses: [ { content: "not json at all", input_tokens: 1, output_tokens: 1 } ]
    )

    assert result.failure?
    assert result.errors.any?
  end
end
