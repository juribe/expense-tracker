# frozen_string_literal: true

require "test_helper"

# HeuristicResolver escalation: when only the category is weak, a small
# category-suggestion call (or free stored knowledge) fills the gap and the
# text still resolves deterministically. Any other weak signal escalates to
# the full AI parse without spending the small call.
class ExpenseResolverHeuristicResolverTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 9, 16)

  setup do
    @user = User.create!(name: "Resolver Heuristic", email: "heuristic@example.com", password: "password123")
    @restaurants = Category.create!(name: "Restaurants", is_default: true, category_type: "expense")
  end

  def resolve(text)
    ExpenseResolver::HeuristicResolver.call(
      text: text,
      user: @user,
      categories: Category.for_user(@user).expenses.order(:name).to_a
    )
  end

  def stub_category_suggestion(data, confidence: 0.9, ok: true)
    suggestion = Struct.new(:ok?, :data, :confidence, :error).new(ok, data, confidence, nil)
    calls = []
    stub_method(Ai::Router, :call, ->(task: nil, **_kwargs) {
      calls << task
      raise ArgumentError, "unexpected AI task: #{task}" unless task == :category_suggestion

      suggestion
    }) do
      yield calls
    end
  end

  # The fill feature reads AI_DISABLE_CATEGORY_FILL from the environment; the
  # tests below exercise it explicitly so they stay independent of .env.
  def with_category_fill_enabled(&block)
    with_env({ "AI_DISABLE_CATEGORY_FILL" => nil }, &block)
  end

  test "a weak category is filled by a small suggestion call and resolves deterministically" do
    with_category_fill_enabled do
      stub_category_suggestion({ "0" => "Spa" }) do |calls|
        resolution = resolve("me gasté 95.000 en spa")

        assert resolution.resolved?
        entry = resolution.entries.first
        assert_equal "Spa", entry.category_suggestion
        assert_operator entry.confidence, :>=, 0.8
        assert_equal [ :category_suggestion ], calls
      end
    end
  end

  test "stored knowledge fills the category with no AI call at all" do
    with_category_fill_enabled do
      spa = Category.create!(name: "Spa", is_default: true, category_type: "expense")
      ActivityClassification.record!(user: @user, name: "Spa", category: spa, source: "user")

      stub_method(Ai::Router, :call, ->(**_kwargs) { raise "no AI expected" }) do
        resolution = resolve("me gasté 95.000 en spa")

        assert resolution.resolved?
        entry = resolution.entries.first
        assert_equal "Spa", entry.category
        assert_nil entry.category_suggestion
      end
    end
  end

  test "a below-threshold suggestion escalates to the full AI parse" do
    with_category_fill_enabled do
      stub_category_suggestion({ "0" => "Spa" }, confidence: 0.5) do
        refute resolve("me gasté 95.000 en spa").resolved?
      end
    end
  end

  test "a failing suggestion call escalates to the full AI parse" do
    with_category_fill_enabled do
      stub_category_suggestion(nil, ok: false) do
        refute resolve("me gasté 95.000 en spa").resolved?
      end
    end
  end

  test "a weak amount never spends the small category call" do
    stub_method(Ai::Router, :call, ->(**_kwargs) { raise "no AI expected" }) do
      # Bare "50" reads at 0.7 confidence: below the deterministic gate even
      # after a perfect category, so only the full parse can help.
      refute resolve("50 en almuerzo").resolved?
    end
  end

  test "AI_DISABLE_CATEGORY_FILL escalates without spending any AI call" do
    with_env({ "AI_DISABLE_CATEGORY_FILL" => "true" }) do
      stub_method(Ai::Router, :call, ->(**_kwargs) { raise "no AI expected" }) do
        resolution = resolve("me gasté 95.000 en spa")

        refute resolution.resolved?
      end
    end
  end
end
