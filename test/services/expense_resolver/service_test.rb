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
end
