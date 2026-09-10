# frozen_string_literal: true

require "test_helper"

module Expenses
  class ActivityClassifierTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Classifier User", email: "classifier@example.com", password: "password123")
      @food = Category.create!(name: "Comida y restaurantes", is_default: true, category_type: "expense")
      @transport = Category.create!(name: "Transporte", is_default: true, category_type: "expense")
    end

    test "reuses a stored user classification first" do
      ActivityClassification.record!(user: @user, name: "DIDI FOOD", category: @food, source: "user")

      result = ActivityClassifier.call(user: @user, activity: "DIDI FOOD")

      assert_equal "cached_user", result[:source]
      assert_equal @food, result[:category]
    end

    test "reuses a stored AI classification without new AI work" do
      ActivityClassification.record!(user: @user, name: "UBER", category: @transport, source: "ai")

      result = ActivityClassifier.call(user: @user, activity: "UBER *00912")

      assert_equal "cached_ai", result[:source]
      assert_equal @transport, result[:category]
    end

    test "falls back to a deterministic category-name rule" do
      result = ActivityClassifier.call(user: @user, activity: "Taxi - transporte")

      assert_equal "rule", result[:source]
      assert_equal @transport, result[:category]
      assert_equal 1, @user.activity_classifications.count
    end

    test "returns fallback when nothing is known" do
      result = ActivityClassifier.call(user: @user, activity: "ALGO DESCONOCIDO XYZ")

      assert_equal "fallback", result[:source]
      assert_nil result[:category]
    end

    test "record: false does not persist rule matches" do
      result = ActivityClassifier.call(user: @user, activity: "Taxi - transporte", record: false)

      assert_equal "rule", result[:source]
      assert_equal 0, @user.activity_classifications.count
    end

    test "classifications are isolated between users" do
      other = User.create!(name: "Other", email: "other-classifier@example.com", password: "password123")
      ActivityClassification.record!(user: @user, name: "DIDI FOOD", category: @food, source: "ai")

      result = ActivityClassifier.call(user: other, activity: "DIDI FOOD")

      assert_equal "fallback", result[:source]
    end
  end
end
