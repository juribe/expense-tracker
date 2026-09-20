# frozen_string_literal: true

require "test_helper"

module Categories
  # Categories::Decision is the single place where the category outcome
  # (resolved / kept / suggested / none) and its warnings are decided for
  # every channel, so every branch is covered here directly.
  class DecisionTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Decision User", email: "decision@example.com", password: "password123")
    end

    test "a matching category resolves with no warnings" do
      restaurants = Category.create!(name: "Restaurants", is_default: true, category_type: "expense")

      result = Decision.call(user: @user, name: "restaurants", activity: "almuerzo")

      assert_equal restaurants, result.category
      assert_equal "Restaurants", result.category_name
      assert_nil result.suggested_category_name
      assert_empty result.warnings
      assert_not result.suggestion?
    end

    test "an unmatched but plausible name is kept with a warning" do
      result = Decision.call(user: @user, name: "mascotas", activity: "comida para el perro")

      assert_nil result.category
      assert_equal "mascotas", result.category_name
      assert_equal "mascotas", result.suggested_category_name
      assert result.warnings.any? { |warning| warning.include?("mascotas") }
    end

    test "a rejected name is replaced by a cleaned suggestion" do
      Category.create!(name: "Servicios públicos", is_default: true, category_type: "expense")

      result = Decision.call(user: @user, name: "Servicios públicos", activity: "pagué 250 lucas de Microsoft 365")

      assert_nil result.category
      assert_equal "Suscripciones", result.category_name
      assert_equal "Suscripciones", result.suggested_category_name
      assert result.warnings.any? { |warning| warning.include?("Suscripciones") }
    end

    test "a blank name with a known streaming activity suggests Entretenimiento" do
      Category.create!(name: "Entretenimiento", is_default: true, category_type: "expense")

      result = Decision.call(user: @user, name: nil, activity: "Netflix 29.900")

      assert_nil result.category
      assert_equal "Entretenimiento", result.category_name
      assert_equal "Entretenimiento", result.suggested_category_name
      assert result.warnings.any? { |warning| warning.include?("Entretenimiento") }
    end

    test "a blank name with no scannable activity leaves everything empty" do
      result = Decision.call(user: @user, name: nil, activity: nil)

      assert_nil result.category
      assert_nil result.category_name
      assert_nil result.suggested_category_name
      assert result.warnings.any? { |warning| warning.include?("could not determine") }
    end

    test "parking activities override the AI's Vivienda label" do
      transporte = Category.create!(name: "Transporte", is_default: true, category_type: "expense")
      Category.create!(name: "Vivienda", is_default: true, category_type: "expense")

      result = Decision.call(user: @user, name: "Vivienda", activity: "gasté en parqueadero")

      assert_equal transporte, result.category
      assert_empty result.warnings
    end
  end
end
