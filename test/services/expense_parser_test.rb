# frozen_string_literal: true

require "test_helper"

class ExpenseParserTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Parser User", email: "parser@example.com", password: "password123")
    @restaurants = Category.create!(name: "Restaurants", is_default: true, category_type: "expense")
    @parking = Category.create!(name: "Parking", is_default: true, category_type: "expense")
    @gasoline = Category.create!(name: "Gasoline", is_default: true, category_type: "expense")
    @groceries = Category.create!(name: "Groceries", is_default: true, category_type: "expense")
    @saved_api_key = ENV.delete("MISTRAL_API_KEY")
  end

  teardown do
    ENV["MISTRAL_API_KEY"] = @saved_api_key
  end

  # 2026-08-22 is a Saturday.
  TODAY = Date.new(2026, 8, 22)

  def parse(text)
    ExpenseParser.call(text: text, user: @user, today: TODAY)
  end

  test "parses multiple expenses from a single message" do
    result = parse("Me gasté 50 mil en un restaurante y 20 mil en parqueadero")

    assert_equal "heuristic", result[:engine]
    assert_equal 2, result[:expenses].length

    first = result[:expenses][0]
    assert_equal 50_000.0, first[:amount]
    assert_equal "Restaurante", first[:description]
    assert_equal @restaurants.id, first[:category_id]
    assert_equal "2026-08-22", first[:transaction_date]
    refute first[:create_category]

    second = result[:expenses][1]
    assert_equal 20_000.0, second[:amount]
    assert_equal "Parqueadero", second[:description]
    assert_equal @parking.id, second[:category_id]
    refute second[:create_category]
  end

  test "understands Colombian currency expressions" do
    assert_equal 50_000.0, parse("50 mil en almuerzo")[:expenses][0][:amount]
    assert_equal 50_000.0, parse("Me gasté 50 lucas en almuerzo")[:expenses][0][:amount]
    assert_equal 80_000.0, parse("Gasté 80k en gasolina")[:expenses][0][:amount]
    assert_equal 50_000.0, parse("pagué 50.000 pesos en el mercado")[:expenses][0][:amount]
    assert_equal 500_000.0, parse("medio millón en arriendo")[:expenses][0][:amount]
    assert_equal 50_000.0, parse("cincuenta mil en cine")[:expenses][0][:amount]
    assert_equal 250_000.0, parse("un cuarto de millón en ropa")[:expenses][0][:amount]
  end

  test "maps descriptions to existing user categories" do
    result = parse("Gasté 80 mil en gasolina y 25 mil en parqueadero")

    gasoline = result[:expenses][0]
    parking = result[:expenses][1]

    assert_equal @gasoline.id, gasoline[:category_id]
    assert_equal "Gasoline", gasoline[:category_name]
    refute gasoline[:create_category]

    assert_equal @parking.id, parking[:category_id]
    refute parking[:create_category]
  end

  test "suggests a new category when none matches" do
    result = parse("Gasté 30 mil en la veterinaria del perro")

    expense = result[:expenses].first
    assert_nil expense[:category_id]
    assert expense[:create_category]
    assert_equal "Pet Care", expense[:category_name]
  end

  test "flags unknown categories as low confidence with a warning" do
    result = parse("gasté 10 mil en xilofono")

    expense = result[:expenses].first
    assert expense[:create_category]
    assert_equal "Xilofono", expense[:category_name]
    assert_operator expense[:confidence], :<, ExpenseParser::LOW_CONFIDENCE_THRESHOLD
    assert expense[:low_confidence]
    assert expense[:warnings].any?
  end

  test "detects relative dates: hoy" do
    result = parse("Hoy gasté 30 mil en almuerzo")
    assert_equal "2026-08-22", result[:expenses][0][:transaction_date]
  end

  test "detects relative dates: ayer" do
    result = parse("Ayer gasté 100 mil en gasolina")
    assert_equal "2026-08-21", result[:expenses][0][:transaction_date]
  end

  test "detects relative dates: anteayer takes precedence over ayer" do
    result = parse("anteayer gasté 5 mil en cafe")
    assert_equal "2026-08-20", result[:expenses][0][:transaction_date]
  end

  test "resolves weekdays to the most recent past occurrence" do
    result = parse("El lunes gasté 50 mil en mercado")
    assert_equal "2026-08-17", result[:expenses][0][:transaction_date]
  end

  test "each expense keeps its own date in mixed messages" do
    result = parse("Ayer gasté 100 mil en gasolina y hoy gaste 30 mil en almuerzo")

    assert_equal "2026-08-21", result[:expenses][0][:transaction_date]
    assert_equal "2026-08-22", result[:expenses][1][:transaction_date]
  end

  test "defaults to today when no date expression is present" do
    result = parse("50 mil en almuerzo")
    assert_equal "2026-08-22", result[:expenses][0][:transaction_date]
  end

  test "returns no expenses for text without amounts" do
    result = parse("hola que tal")

    assert_empty result[:expenses]
  end

  test "includes the transcription and confidence values" do
    result = parse("50 mil en almuerzo")

    assert_equal "50 mil en almuerzo", result[:transcription]
    assert_instance_of Float, result[:expenses][0][:confidence]
  end

  test "detects the money source mentioned by name" do
    source = @user.money_sources.create!(name: "Cuenta Nequi", kind: "account", bank: "Bancolombia")
    result = parse("Me gasté 50 mil en almuerzo con la cuenta nequi")

    expense = result[:expenses].first
    assert_equal source.id, expense[:money_source_id]
    assert_equal source.name, expense[:money_source_name]
  end

  test "detects the money source mentioned by tag" do
    source = @user.money_sources.create!(name: "Visa", kind: "credit_card")
    source.tags.create!(value: "tarjeta clásica")
    result = parse("Pag 50 mil en el restaurante con la tarjeta clásica")

    assert_equal source.id, result[:expenses].first[:money_source_id]
  end

  test "detects the money source by bank name" do
    source = @user.money_sources.create!(name: "Ahorros", kind: "account", bank: "Davivienda")
    result = parse("pagué 30 mil con davivienda en el mercado")

    assert_equal source.id, result[:expenses].first[:money_source_id]
  end

  test "ignores inactive money sources when detecting" do
    @user.money_sources.create!(name: "Vieja tarjeta", kind: "credit_card", active: false)
    result = parse("gasté 10 mil con la vieja tarjeta en el cine")

    assert_nil result[:expenses].first[:money_source_id]
  end

  test "returns nil money source when none is mentioned" do
    result = parse("50 mil en almuerzo")

    assert_nil result[:expenses].first[:money_source_id]
    assert_nil result[:expenses].first[:money_source_name]
  end

  test "applies a single mentioned money source to every detected expense" do
    source = @user.money_sources.create!(name: "Nequi", kind: "wallet")
    result = parse("gasté 50 mil en restaurante y 20 mil en parqueadero desde nequi")

    assert_equal source.id, result[:expenses][0][:money_source_id]
    assert_equal source.id, result[:expenses][1][:money_source_id]
  end

  test "uses AI results when the provider succeeds" do
    parser_class = Class.new(ExpenseParser) do
      define_method(:parse_with_ai) do
        [
          {
            "amount" => 120_000,
            "category" => "Pet Care",
            "description" => "Veterinaria",
            "transaction_date" => "2026-08-20",
            "confidence" => 0.98,
            "create_category" => true
          }
        ]
      end
    end
    ENV["MISTRAL_API_KEY"] = "test-key"

    result = parser_class.call(text: "gasté 120 mil en veterinaria", user: @user, today: TODAY)

    assert_equal "ai", result[:engine]
    expense = result[:expenses].first
    assert_equal 120_000.0, expense[:amount]
    assert_equal "Pet Care", expense[:category_name]
    assert_equal "2026-08-20", expense[:transaction_date]
    assert expense[:create_category]
  end

  test "falls back to heuristics when the AI call fails" do
    parser_class = Class.new(ExpenseParser) do
      define_method(:parse_with_ai) do
        raise ExpenseParser::AIError, "boom"
      end
    end
    ENV["MISTRAL_API_KEY"] = "test-key"

    result = parser_class.call(text: "50 mil en almuerzo", user: @user, today: TODAY)

    assert_equal "heuristic", result[:engine]
    assert result[:errors].any? { |message| message.include?("AI parsing failed") }
    assert_equal 50_000.0, result[:expenses][0][:amount]
  end

  test "drops invalid AI entries instead of persisting bad data" do
    parser_class = Class.new(ExpenseParser) do
      define_method(:parse_with_ai) do
        [
          { "amount" => -5, "category" => "Others", "description" => "Bad", "transaction_date" => "2026-08-22" },
          { "amount" => 9_999, "category" => "Groceries", "description" => "Mercado", "transaction_date" => "2026-08-21" }
        ]
      end
    end
    ENV["MISTRAL_API_KEY"] = "test-key"

    result = parser_class.call(text: "test", user: @user, today: TODAY)

    assert_equal 1, result[:expenses].length
    assert_equal 9_999.0, result[:expenses][0][:amount]
    assert_equal @groceries.id, result[:expenses][0][:category_id]
    assert result[:errors].any?
  end
end
