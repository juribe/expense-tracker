# frozen_string_literal: true

require "test_helper"

# ExpenseResolver::Service orchestration: a confident deterministic pass runs
# without any AI call; low-confidence or unresolvable text is handed to the AI
# (NaturalLanguageParser), and an AI failure surfaces as a controlled error
# with no heuristic fallback.
class ExpenseResolverServiceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Resolver User", email: "resolver@example.com", password: "password123")
    Category.create!(name: "Restaurants", is_default: true, category_type: "expense")
  end

  def ai_entries
    [ Ai::Tasks::ParsedExpense.new(
      original_text: "pagué 30 mil en servicios",
      amount: 30_000,
      date: Date.current,
      description: "servicios",
      category: "Restaurants",
      money_source_hint: nil,
      confidence: 0.8
    ) ]
  end

  def with_stubbed_ai(entries:, error: nil)
    result = error ? ServiceResult.error(error) : ServiceResult.success(entries)
    calls = []
    stub_method(ExpenseResolver::NaturalLanguageParser, :call, ->(**kwargs) { calls << kwargs; result }) do
      yield calls
    end
  end

  # Forces the AI path (bypassing the deterministic pass) and injects the
  # entries the AI would have returned for the given text.
  def with_forced_ai(entries:, text:)
    unresolved = ExpenseResolver::HeuristicResolver::Resolution.new(nil)
    stub_method(ExpenseResolver::HeuristicResolver, :call, ->(**_kwargs) { unresolved }) do
      with_stubbed_ai(entries: entries) do
        ExpenseResolver::Service.call(text: text, user: @user)
      end
    end
  end

  test "a confidently resolvable message skips the AI call" do
    with_stubbed_ai(entries: ai_entries) do |calls|
      result = ExpenseResolver::Service.call(text: "gasté 50 mil en almuerzo", user: @user)

      assert result.success?
      assert_equal 1, result.result.length
      candidate = result.result.first
      assert_equal 50_000, candidate.amount
      assert_equal "Restaurants", candidate.category_name
      assert_equal "heuristic", candidate.classification_source
      assert_empty calls
    end
  end

  test "the deterministic pass records an extraction step and a deterministic AiRequest" do
    recording = Expenses::Processors::Recording.new
    with_env({ "MISTRAL_API_KEY" => "test-key" }) do
      ExpenseResolver::Service.call(text: "gasté 50 mil en almuerzo", user: @user, recording: recording)
    end

    assert recording.steps[:extraction].present?
    row = AiRequest.where(strategy: "deterministic").last
    assert_not_nil row
    assert_equal "expense_extraction", row.task
    assert_equal @user.id, row.user_id
  end

  test "a low-confidence heuristic pass hands the text over to the AI" do
    with_stubbed_ai(entries: ai_entries) do |calls|
      result = ExpenseResolver::Service.call(text: "50 en almuerzo", user: @user)

      assert result.success?
      assert_equal 1, result.result.length
      assert_equal 30_000, result.result.first.amount
      assert_equal "ai", result.result.first.classification_source
      assert_equal 1, calls.length
    end
  end

  test "an AI failure returns a controlled error without heuristic fallback" do
    with_stubbed_ai(entries: ai_entries, error: [ "AI parsing failed." ]) do
      result = ExpenseResolver::Service.call(text: "pagué algo raro con plata", user: @user)

      assert result.failure?
      assert_equal [ "AI parsing failed." ], result.errors
    end
  end

  test "basic validations still apply" do
    assert ExpenseResolver::Service.call(text: "", user: @user).failure?
    assert ExpenseResolver::Service.call(text: "gasté 50 mil", user: nil).failure?
  end

  # === Ported from the old ExpenseParser suite ==============================

  test "detects the money source and applies it to every detected expense" do
    Category.create!(name: "Parking", is_default: true, category_type: "expense")
    source = @user.money_sources.create!(name: "Nequi", kind: "wallet")

    result = ExpenseResolver::Service.call(
      text: "gasté 50 mil en restaurante y 20 mil en parqueadero desde nequi",
      user: @user
    )

    assert result.success?
    assert_equal [ source.id, source.id ], result.result.map(&:money_source_id)
    assert_equal [ "Nequi", "Nequi" ], result.result.map(&:money_source_name)
  end

  test "ignores inactive money sources when detecting" do
    @user.money_sources.create!(name: "Vieja tarjeta", kind: "credit_card", active: false)

    result = ExpenseResolver::Service.call(text: "gasté 50 mil en almuerzo con la vieja tarjeta", user: @user)

    assert result.success?
    assert_nil result.result.first.money_source_id
  end

  test "AI misexpanded amounts are corrected from the deterministic reading" do
    result = nil
    stub_method(ExpenseResolver::NaturalLanguageParser, :call, ->(**_kwargs) {
      ServiceResult.success([ Ai::Tasks::ParsedExpense.new(
        original_text: "20 mil en algo raro",
        amount: 2_000_000, date: Date.current, description: "algo raro",
        category: "Restaurants", money_source_hint: nil, confidence: 0.9
      ) ])
    }) do
      result = ExpenseResolver::Service.call(text: "20 mil en algo raro", user: @user)
    end

    assert result.success?
    assert_equal 20_000, result.result.first.amount
    assert_equal "ai", result.result.first.classification_source
  end

  test "the deterministic reading survives when a single fragment misattributes another expense's amount" do
    # Fragment mentions two distinct amounts; the heuristic scan would grab
    # the first one while the AI's own amount is the second.
    entry = Ai::Tasks::ParsedExpense.new(
      original_text: "compré una camisa de 140.000 y de paso pagué una deuda de 50.000",
      amount: 50_000, date: Date.current, description: "camisa",
      category: nil, category_suggestion: "Ropa", money_source_hint: nil, confidence: 0.9
    )

    result = with_forced_ai(
      entries: [ entry ],
      text: "compré una camisa de 140.000 y de paso pagué una deuda de 50.000"
    )

    assert result.success?
    assert_equal 50_000, result.result.first.amount
  end

  test "multi-expense messages trust the AI amounts without heuristic re-scan" do
    # Per-entry fragments are correct, but the heuristic scan of "y otras 20
    # en parqueadero" would read bare "20" as 20 COP and override the AI.
    entries = [
      Ai::Tasks::ParsedExpense.new(
        original_text: "Hoy me gasté como 60 lucas comiendo con la familia",
        amount: 60_000, date: Date.current, description: "comida con la familia",
        category: "Restaurants", money_source_hint: nil, confidence: 0.9
      ),
      Ai::Tasks::ParsedExpense.new(
        original_text: "y otras 20 en parqueadero",
        amount: 20_000, date: Date.current, description: "parqueadero",
        category: "Parking", money_source_hint: nil, confidence: 0.9
      )
    ]

    result = with_forced_ai(
      entries: entries,
      text: "Hoy me gasté como 60 lucas comiendo con la familia y otras 20 en parqueadero"
    )

    assert result.success?
    assert_equal [ 60_000, 20_000 ], result.result.map(&:amount)
  end

  test "a low-confidence bare-number scan never overrides the AI amount" do
    entry = Ai::Tasks::ParsedExpense.new(
      original_text: "gasté 20 en parqueadero",
      amount: 20_000, date: Date.current, description: "parqueadero",
      category: "Parking", money_source_hint: nil, confidence: 0.9
    )

    result = with_forced_ai(entries: [ entry ], text: "gasté 20 en parqueadero")

    assert result.success?
    assert_equal 20_000, result.result.first.amount
  end

  test "the AI date wins when a fragment mentions several distinct dates" do
    yesterday = Date.current - 1
    entry = Ai::Tasks::ParsedExpense.new(
      original_text: "ayer compré mercado por 100.000 y hoy pagué el arriendo de 800.000",
      amount: 100_000, date: yesterday, description: "mercado",
      category: nil, money_source_hint: nil, confidence: 0.9
    )

    result = with_forced_ai(
      entries: [ entry ],
      text: "ayer compré mercado por 100.000 y hoy pagué el arriendo de 800.000"
    )

    assert result.success?
    assert_equal yesterday, result.result.first.date
  end

  test "shared full-message fragments keep the AI amounts and dates for every expense" do
    full_text = "Salí con mi esposa al centro comercial, primero almorzamos por 95.000 y después compré una camisa de 140.000 con la tarjeta."
    yesterday = Date.current - 1
    entries = [
      Ai::Tasks::ParsedExpense.new(
        original_text: full_text, amount: 95_000, date: yesterday,
        description: "almuerzo", category: "Restaurants",
        money_source_hint: nil, confidence: 0.9
      ),
      Ai::Tasks::ParsedExpense.new(
        original_text: full_text, amount: 140_000, date: Date.current,
        description: "camisa", category: nil, category_suggestion: "Ropa",
        money_source_hint: nil, confidence: 0.9
      )
    ]

    result = with_forced_ai(entries: entries, text: full_text)

    assert result.success?
    assert_equal [ 95_000, 140_000 ], result.result.map(&:amount)
    assert_equal [ yesterday, Date.current ], result.result.map(&:date)
    assert_equal "Ropa", result.result.last.suggested_category_name
  end

  test "an AI category suggestion names the candidate when no category matched" do
    entry = Ai::Tasks::ParsedExpense.new(
      original_text: "transferencia a Juan por concepto de videojuegos",
      amount: 50_000,
      date: Date.current,
      description: "transferencia a Juan por concepto de videojuegos",
      category: nil,
      category_suggestion: "Videojuegos",
      money_source_hint: nil,
      confidence: 0.9
    )

    result = nil
    with_stubbed_ai(entries: [ entry ]) do
      result = ExpenseResolver::Service.call(text: "transferencia a Juan por concepto de videojuegos", user: @user)
    end

    assert result.success?
    candidate = result.result.first
    assert_nil candidate.category_id
    assert_equal "Videojuegos", candidate.suggested_category_name
    assert_equal "Videojuegos", candidate.category_name
  end

  test "a matching rule overrides the resolver's category suggestion" do
    apps = Category.create!(name: "Apps", is_default: true, category_type: "expense")
    TransactionRule.create!(user: @user, merchant_contains: nil,
                            description_contains: "didi", category_id: apps.id)

    result = ExpenseResolver::Service.call(text: "50 mil en didi en un restaurante", user: @user)

    assert result.success?
    candidate = result.result.first
    assert_equal apps.id, candidate.category_id
    assert_equal apps.name, candidate.category_name
    assert_nil candidate.suggested_category_name
  end

  test "a user correction overrides earlier AI knowledge" do
    restaurants = Category.find_by!(name: "Restaurants")
    ActivityClassification.record!(user: @user, name: "DIDI FOOD", category: restaurants, source: "strong_ai")

    other = Category.create!(name: "Food Delivery", is_default: true, category_type: "expense")
    ActivityClassification.record!(user: @user, name: "DIDI FOOD", category: other, source: "user")

    assert_equal other.id, ActivityClassification.lookup(user: @user, name: "DIDI FOOD").category_id

    # An AI source must never overwrite the user correction.
    ActivityClassification.record!(user: @user, name: "DIDI FOOD", category: restaurants, source: "cheap_ai")
    assert_equal other.id, ActivityClassification.lookup(user: @user, name: "DIDI FOOD").category_id
  end
end
