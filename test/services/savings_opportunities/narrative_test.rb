# frozen_string_literal: true

require "test_helper"

class SavingsOpportunitiesNarrativeTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Narrative User", email: "savings_narrative@example.com", password: "password123")
    @food = Category.create!(name: "Restaurantes", is_default: true, category_type: "expense")
    @bank = @user.money_sources.create!(name: "Cuenta", kind: "account", active: true,
                                        starting_balance: 1_000_000_000)
    @date = Date.new(2026, 10, 15)
    @cache = ActiveSupport::Cache::MemoryStore.new
    [ 7, 8, 9 ].each do |month|
      expense(-600_000, date: Date.new(2026, month, 5))
    end
    expense(-900_000)
    @analysis = SavingsOpportunities::Analysis.new(user: @user, date: @date).call
  end

  def expense(amount, date: Date.new(2026, 10, 5))
    Expense.create!(user: @user, category: @food, money_source: @bank, amount: amount,
                    date: date, description: "Restaurante")
  end

  def narrative(router: Ai::Router, ai_available: nil)
    SavingsOpportunities::Narrative.new(user: @user, analysis: @analysis, cache: @cache,
                                        router: router, ai_available: ai_available)
  end

  class FakeRouter
    def initialize(result)
      @result = result
    end

    def call(**_options)
      @result
    end
  end

  class RecordingRouter
    attr_reader :call_args

    def initialize(result)
      @result = result
    end

    def call(**options)
      @call_args = options
      @result
    end
  end

  def ai_result(payload)
    Ai::Router::Result.new(ok?: true, data: payload, confidence: nil, strategy: "strong_ai", error: nil)
  end

  test "builds a deterministic summary when AI is not used" do
    result = narrative.deterministic

    assert_equal "deterministic", result["source"]
    assert result["summary"].present?
    assert result["highlights"].key?("category:#{@food.id}")
  end

  test "the deterministic summary reports insufficient history instead of inventing recommendations" do
    user = User.create!(name: "New", email: "savings_narrative_new@example.com", password: "password123")
    bank = user.money_sources.create!(name: "Bank", kind: "account", active: true, starting_balance: 1_000_000)
    Expense.create!(user: user, category: @food, money_source: bank, amount: -50_000,
                    date: @date, description: "x")
    analysis = SavingsOpportunities::Analysis.new(user: user, date: @date).call

    result = SavingsOpportunities::Narrative.new(user: user, analysis: analysis, cache: @cache).deterministic

    assert_equal "insufficient_history", result["state"]
    assert result["summary"].present?
    assert_empty result["highlights"]
  end

  test "mentions configured recurring payments when there is no history to compare" do
    user = User.create!(name: "New Config", email: "savings_narrative_configured@example.com", password: "password123")
    bank = user.money_sources.create!(name: "Bank", kind: "account", active: true, starting_balance: 1_000_000)
    Expense.create!(user: user, category: @food, money_source: bank, amount: -50_000,
                    date: @date, description: "x")
    template = RecurringTemplate.create!(user: user, category: @food, kind: "expense",
                                         description: "Netflix", amount: 29_900, frequency: "monthly",
                                         source: "manual", payment_day: 12)
    analysis = SavingsOpportunities::Analysis.new(user: user, date: @date).call

    result = SavingsOpportunities::Narrative.new(user: user, analysis: analysis, cache: @cache).deterministic

    assert_equal "insufficient_history", result["state"]
    assert_includes result["summary"], "pago recurrente"
    assert result["highlights"].key?("recurring:template-#{template.id}")
  end

  test "merges AI text only for references that exist in the computed analysis" do
    payload = {
      "summary" => "Resumen generado por el modelo.",
      "highlights" => [
        { "reference" => "category:#{@food.id}",
          "explanation" => "Explicación válida.",
          "recommendation" => "Recomendación válida." },
        { "reference" => "category:00000000-0000-0000-0000-000000000000",
          "explanation" => "Inventado.",
          "recommendation" => "Inventado." }
      ]
    }

    result = narrative(router: FakeRouter.new(ai_result(payload)), ai_available: true).generate!

    assert_equal "ai", result["source"]
    assert_equal "Resumen generado por el modelo.", result["summary"]
    assert_equal "Explicación válida.", result["highlights"]["category:#{@food.id}"]["explanation"]
    refute result["highlights"].key?("category:00000000-0000-0000-0000-000000000000")
  end

  test "falls back to deterministic results when the provider fails" do
    failure = Ai::Router::Result.new(ok?: false, data: nil, confidence: nil, strategy: nil,
                                     error: "provider down")
    result = narrative(router: FakeRouter.new(failure), ai_available: true).generate!

    assert_equal "deterministic", result["source"]
    assert result["summary"].present?
    assert_includes result["error"], "provider down"
  end

  test "stores and reuses the generated narrative" do
    service = narrative(router: FakeRouter.new(ai_result({ "summary" => "Guardado.", "highlights" => [] })),
                        ai_available: true)
    service.generate!

    cached = narrative.fetch

    assert_equal "Guardado.", cached["summary"]
    assert_equal "ai", cached["source"]
  end

  test "fetch returns nil when nothing has been generated" do
    assert_nil narrative.fetch
  end

  test "the AI context contains aggregated data and allowed references only" do
    router = RecordingRouter.new(ai_result({ "summary" => "ok", "highlights" => [] }))

    narrative(router: router, ai_available: true).generate!

    assert_equal :savings_opportunity_analysis, router.call_args[:task]
    assert_includes router.call_args[:context][:allowed_references], "category:#{@food.id}"
    refute router.call_args[:input].to_s.include?(@user.email)
  end
end
