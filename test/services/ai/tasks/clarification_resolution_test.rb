# frozen_string_literal: true

require "test_helper"

module Ai
  module Tasks
    class ClarificationResolutionTest < ActiveSupport::TestCase
      setup do
        @task = ClarificationResolution.new
        @context = {
          candidates: [ { index: 1, description: "Éxito", amount: 40_000, date: Date.current,
                          category: nil, money_source: nil, missing_fields: %w[category_id money_source_id] } ],
          question: "¿En qué categoría encaja?",
          original_message: "40 mil en Éxito",
          categories: %w[Transporte Restaurants],
          money_source_identifiers: %w[Davibank Nequi],
          today: Date.current
        }
      end

      test "uses the default tier cascade so it still runs when the strong tier is disabled" do
        assert_includes @task.tiers, :cheap
        assert_includes @task.tiers, :strong
      end

      test "resolves through the cheap tier when the strong tier is disabled" do
        stub_method(Ai.configuration, :strong_tier_disabled?, -> { true }) do
          response = Provider::Response.new(
            content: { resolutions: [ { index: 1, resolved: { category: "Transporte" } } ],
                       new_expense_text: nil }.to_json,
            model: "fake", input_tokens: 10, output_tokens: 10
          )
          fake_provider = Object.new
          fake_provider.define_singleton_method(:configured?) { true }
          fake_provider.define_singleton_method(:chat) { |**_kwargs| response }

          stub_method(Ai::Providers, :for, ->(_tier) { fake_provider }) do
            result = Ai::Router.call(task: :clarification_resolution, input: "transporte", context: @context)
            assert result.ok?, "expected cheap tier to serve the task: #{result.error.inspect}"
            assert_equal 1, result.data[:resolutions].size
          end
        end
      end

      test "parse normalizes resolution entries and drops unknown keys" do
        parsed = @task.parse(
          { "resolutions" => [
            { "index" => "1", "resolved" => { "category" => "Transporte", "evil" => "x" } },
            { "index" => 2, "unresolved" => true }
          ], "new_expense_text" => "50 mil en cine" }.to_json,
          "reply", @context
        )

        assert_equal 1, parsed[:data][:resolutions][0][:index]
        assert_equal({ "category" => "Transporte" }, parsed[:data][:resolutions][0][:resolved])
        assert parsed[:data][:resolutions][1][:unresolved]
        assert_equal "50 mil en cine", parsed[:data][:new_expense_text]
      end

      test "parse raises on a non-array resolutions payload" do
        assert_raises(ClarificationResolution::InvalidResponse) do
          @task.parse({ "nope" => true }.to_json, "reply", @context)
        end
      end

      test "parse propagates new_category_name and drops list resolutions for it" do
        parsed = @task.parse(
          { "resolutions" => [
            { "index" => 1, "resolved" => { "money_source_hint" => "davibank" } }
          ],
            "new_category_name" => "Animacion", "new_expense_text" => nil }.to_json,
          "animacion", @context
        )

        assert_equal "Animacion", parsed[:data][:new_category_name]
        assert_equal 1, parsed[:data][:resolutions].size
      end

      test "parse leaves new_category_name blank when absent" do
        parsed = @task.parse(
          { "resolutions" => [ { "index" => 1, "resolved" => { "category" => "Transporte" } } ],
            "new_expense_text" => nil }.to_json,
          "transporte", @context
        )

        assert_nil parsed[:data][:new_category_name].presence
      end
    end
  end
end
