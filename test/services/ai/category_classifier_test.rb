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
  end
end
