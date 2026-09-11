# frozen_string_literal: true

require "test_helper"

module Ai
  class CategoryClassifierTest < ActiveSupport::TestCase
    def parse(raw, activities:, categories:)
      Ai::CategoryClassifier.parse(raw, activities: activities, categories: categories)
    end

    test "maps activities to the exact category names provided" do
      data = parse(
        { "assignments" => [
          { "activity" => "DIDI FOOD", "category" => "Restaurants" },
          { "activity" => "NEQUI PAGO", "category" => "Otros" }
        ] },
        activities: [ "DIDI FOOD", "NEQUI PAGO" ],
        categories: [ "Restaurants", "Otros" ]
      )

      assert_equal "Restaurants", data["didi food"]
      assert_equal "Otros", data["nequi pago"]
    end

    test "ignores categories not in the allowed list and unmapped activities" do
      data = parse(
        { "assignments" => [
          { "activity" => "DIDI FOOD", "category" => "not-a-category" },
          { "activity" => "UNKNOWN", "category" => "Restaurants" }
        ] },
        activities: [ "DIDI FOOD" ],
        categories: [ "Restaurants" ]
      )

      assert_equal({}, data)
    end

    test "null category keeps the activity unclassified" do
      data = parse(
        { "assignments" => [ { "activity" => "DIDI FOOD", "category" => nil } ] },
        activities: [ "DIDI FOOD" ],
        categories: [ "Restaurants" ]
      )

      assert_equal({}, data)
    end

    test "raises on missing assignments array" do
      error = assert_raises(Ai::CategoryClassifier::ExtractionError) do
        parse({ "assignments" => nil }, activities: [ "X" ], categories: [ "Y" ])
      end

      assert_match "assignments", error.message
    end

    # ------------------------------------------------------------- routing

    def routing_user
      @routing_user ||= User.create!(name: "Cls User", email: "cls@example.com", password: "password123")
    end

    def routing_categories
      @routing_categories ||= Category.create!(name: "Restaurants", is_default: true, category_type: "expense")
    end

    def assignments_payload(entries)
      { assignments: entries }.to_json
    end

    test "classifies with the cheap model first and persists the knowledge" do
      routing_categories
      payload = assignments_payload([
        { "activity" => "DIDI FOOD", "category" => "Restaurants", "confidence" => 0.96 }
      ])
      cheap = FakeAiProvider.new(responses: [ payload ])
      strong = FakeAiProvider.new(responses: [])

      result = nil
      stub_method(Ai::Providers, :cheap, ->(*) { cheap }) do
        stub_method(Ai::Providers, :strong, ->(*) { strong }) do
          with_env({ "MISTRAL_API_KEY" => "test-key" }) do
            result = Ai::CategoryClassifier.new.call(
              activities: [ "DIDI FOOD" ], categories: [ "Restaurants" ], user: routing_user
            )
          end
        end
      end

      assert result[:ok?]
      assert_equal "cheap_ai", result[:strategy]
      assert_equal "Restaurants", result[:data]["didi food"]
      assert_equal 0, strong.calls.count

      stored = ActivityClassification.lookup(user: routing_user, name: "DIDI FOOD")
      assert_not_nil stored
      assert_equal "Restaurants", stored.category.name
      assert_equal "cheap_ai", stored.source
    end

    test "escalates to the strong model on low confidence and records its source" do
      routing_categories
      weak = assignments_payload([ { "activity" => "DIDI FOOD", "category" => "Restaurants", "confidence" => 0.5 } ])
      solid = assignments_payload([ { "activity" => "DIDI FOOD", "category" => "Restaurants", "confidence" => 0.99 } ])
      cheap = FakeAiProvider.new(responses: [ weak ])
      strong = FakeAiProvider.new(responses: [ solid ])

      result = nil
      stub_method(Ai::Providers, :cheap, ->(*) { cheap }) do
        stub_method(Ai::Providers, :strong, ->(*) { strong }) do
          with_env({ "MISTRAL_API_KEY" => "test-key" }) do
            result = Ai::CategoryClassifier.new.call(
              activities: [ "DIDI FOOD" ], categories: [ "Restaurants" ], user: routing_user
            )
          end
        end
      end

      assert result[:ok?]
      assert_equal "strong_ai", result[:strategy]
      assert_equal "strong_ai", ActivityClassification.lookup(user: routing_user, name: "DIDI FOOD").source
    end

    test "stored classifications are reused without any AI call" do
      routing_categories
      ActivityClassification.record!(user: routing_user, name: "DIDI FOOD",
                                     category: "Restaurants", source: "user")

      cheap = FakeAiProvider.new(responses: [])
      result = stub_method(Ai::Providers, :cheap, ->(*) { cheap }) do
        with_env({ "MISTRAL_API_KEY" => "test-key" }) do
          Ai::CategoryClassifier.new.call(
            activities: [ "DIDI FOOD" ], categories: [ "Restaurants" ], user: routing_user
          )
        end
      end

      assert result[:ok?]
      assert_equal "cache", result[:strategy]
      assert_equal "Restaurants", result[:data]["didi food"]
      assert_equal 0, cheap.calls.count
    end

    test "batches multiple activities into a single chat request" do
      routing_categories
      payload = assignments_payload([
        { "activity" => "DIDI FOOD", "category" => "Restaurants", "confidence" => 0.98 },
        { "activity" => "UBER", "category" => "Restaurants", "confidence" => 0.95 }
      ])
      cheap = FakeAiProvider.new(responses: [ payload ])

      result = nil
      stub_method(Ai::Providers, :cheap, ->(*) { cheap }) do
        with_env({ "MISTRAL_API_KEY" => "test-key" }) do
          result = Ai::CategoryClassifier.new.call(
            activities: [ "DIDI FOOD", "UBER" ], categories: [ "Restaurants" ], user: routing_user
          )
        end
      end

      assert result[:ok?]
      assert_equal 1, cheap.calls.count
      assert_equal "Restaurants", result[:data]["didi food"]
      assert_equal "Restaurants", result[:data]["uber"]
    end

    test "reports a recoverable failure when every tier fails" do
      cheap = FakeAiProvider.new(responses: [ Ai::Provider::Error.new("AI HTTP 500") ])
      strong = FakeAiProvider.new(responses: [ Ai::Provider::Error.new("AI HTTP 500") ])

      result = nil
      stub_method(Ai::Providers, :cheap, ->(*) { cheap }) do
        stub_method(Ai::Providers, :strong, ->(*) { strong }) do
          with_env({ "MISTRAL_API_KEY" => "test-key" }) do
            result = Ai::CategoryClassifier.new.call(
              activities: [ "DIDI FOOD" ], categories: [ "Restaurants" ], user: routing_user
            )
          end
        end
      end

      refute result[:ok?]
      assert_match(/AI HTTP 500/, result[:error])
    end
  end
end
