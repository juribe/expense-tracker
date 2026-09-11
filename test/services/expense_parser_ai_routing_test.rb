# frozen_string_literal: true

require "test_helper"

# Conversation routing: deterministic → cheap AI → strong AI for
# natural-language expense entry. AI configuration is faked through ENV and
# stubbed providers; no network calls are made.
class ExpenseParserAiRoutingTest < ActiveSupport::TestCase
  AI_ENV = { "MISTRAL_API_KEY" => "test-key" }.freeze

  setup do
    @user = User.create!(name: "Routing User", email: "routing@example.com", password: "password123")
    @restaurants = Category.create!(name: "Restaurants", is_default: true, category_type: "expense")
  end

  TODAY = Date.new(2026, 8, 22)

  def parse(text)
    ExpenseParser.call(text: text, user: @user, today: TODAY)
  end

  def entries(amount: 20_000, confidence: 0.95)
    [ {
      "amount" => amount, "category" => "Restaurants", "description" => "Almuerzo",
      "transaction_date" => TODAY.iso8601, "confidence" => confidence, "create_category" => false
    } ]
  end

  def routing_result(entries:, strategy: "cheap_ai", confidence: 0.95)
    Ai::Router::Result.new(ok?: true, data: entries, strategy: strategy,
                           confidence: confidence, error: nil)
  end

  test "a fully resolvable message avoids AI even when an API key is set" do
    strong = FakeAiProvider.new(responses: [])
    cheap = FakeAiProvider.new(responses: [])

    result = nil
    stub_method(Ai::Providers, :cheap, ->(*) { cheap }) do
      stub_method(Ai::Providers, :strong, ->(*) { strong }) do
        with_env(AI_ENV) { result = parse("gasté 50 mil en almuerzo") }
      end
    end

    assert_equal "heuristic", result[:engine]
    assert_equal 50_000.0, result[:expenses].first[:amount]
    assert_equal 0, cheap.calls.count
    assert_equal 0, strong.calls.count

    row = AiRequest.where(strategy: "deterministic").last
    assert_not_nil row
    assert_equal "expense_extraction", row.task
    assert_equal @user.id, row.user_id
  end

  test "unresolvable messages go to the cheap model and the strong model stays unused" do
    cheap = FakeAiProvider.new(responses: [ { content: { expenses: entries }.to_json, input_tokens: 20, output_tokens: 8 } ])
    strong = FakeAiProvider.new(responses: [])

    result = nil
    stub_method(Ai::Providers, :cheap, ->(*) { cheap }) do
      stub_method(Ai::Providers, :strong, ->(*) { strong }) do
        with_env(AI_ENV) { result = parse("pagué algo raro con plata") }
      end
    end

    assert_equal "ai", result[:engine]
    expense = result[:expenses].first
    assert_equal 20_000.0, expense[:amount]
    assert_equal "Almuerzo", expense[:description]
    assert_equal 1, cheap.calls.count
    assert_equal 0, strong.calls.count

    row = AiRequest.where(strategy: "cheap_ai").last
    assert_equal "ok", row.status
    assert_equal 20, row.input_tokens
  end

  test "a low-confidence cheap extraction escalates to the strong model" do
    shaky = { content: { expenses: entries(confidence: 0.61) }.to_json }
    solid = { content: { expenses: entries(confidence: 0.99) }.to_json }
    cheap = FakeAiProvider.new(responses: [ shaky ])
    strong = FakeAiProvider.new(responses: [ solid ])

    result = nil
    stub_method(Ai::Providers, :cheap, ->(*) { cheap }) do
      stub_method(Ai::Providers, :strong, ->(*) { strong }) do
        with_env(AI_ENV.merge("AI_CHEAP_CONFIDENCE_THRESHOLD" => "0.90")) do
          result = parse("pagué algo raro con plata")
        end
      end
    end

    assert_equal "ai", result[:engine]
    assert_equal 1, cheap.calls.count
    assert_equal 1, strong.calls.count

    assert_equal "low_confidence", AiRequest.where(strategy: "cheap_ai").last.status
    assert_equal "ok", AiRequest.where(strategy: "strong_ai").last.status
    assert AiRequest.where(strategy: "strong_ai").last.escalated
  end

  test "when every AI tier fails the heuristic fallback keeps working" do
    cheap = FakeAiProvider.new(responses: [ Ai::Provider::Error.new("boom") ])
    strong = FakeAiProvider.new(responses: [ Ai::Provider::Error.new("also broken") ])

    result = nil
    stub_method(Ai::Providers, :cheap, ->(*) { cheap }) do
      stub_method(Ai::Providers, :strong, ->(*) { strong }) do
        with_env(AI_ENV) { result = parse("50 mil en membresia misteriosa") }
      end
    end

    assert_equal "heuristic", result[:engine]
    assert_equal 50_000.0, result[:expenses].first[:amount]
    assert result[:errors].any? { |message| message.include?("AI parsing failed") }
  end

  test "a user correction overrides and replaces earlier AI knowledge" do
    category = @restaurants
    ActivityClassification.record!(user: @user, name: "DIDI FOOD", category: category, source: "strong_ai")

    other = Category.create!(name: "Food Delivery", is_default: true, category_type: "expense")
    ActivityClassification.record!(user: @user, name: "DIDI FOOD", category: other, source: "user")

    stored = ActivityClassification.lookup(user: @user, name: "DIDI FOOD")
    assert_equal other.id, stored.category_id
    assert_equal "user", stored.source

    # An AI source must never overwrite the user correction.
    ActivityClassification.record!(user: @user, name: "DIDI FOOD", category: category, source: "cheap_ai")
    assert_equal other.id, ActivityClassification.lookup(user: @user, name: "DIDI FOOD").category_id
  end
end
