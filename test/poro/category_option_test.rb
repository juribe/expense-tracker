# frozen_string_literal: true

require "test_helper"

class CategoryOptionTest < ActiveSupport::TestCase
  test "exposes the category id, name and slug" do
    category = Category.create!(name: "Servicios públicos", is_default: true, category_type: "expense")
    option = CategoryOption.new(category)

    assert_equal category.id, option.id
    assert_equal "Servicios públicos", option.name
    assert_equal "servicios-publicos", option.slug
  end

  test "label is the bare category name" do
    category = Category.create!(name: "Restaurante", is_default: true, category_type: "expense")

    assert_equal "Restaurante", CategoryOption.new(category).label
  end

  test "search_text downcases and strips accents" do
    category = Category.create!(name: "Educación", is_default: true, category_type: "expense")

    assert_equal "educacion", CategoryOption.new(category).search_text
  end

  test "search_text keeps the full name, including hyphen and number suffixes" do
    category = Category.create!(name: "Food-1790712537501", is_default: false, category_type: "expense", user: create_user)

    assert_equal "food 1790712537501", CategoryOption.new(category).search_text
  end

  test "search_text does not drop merchant suffixes the way classification normalization does" do
    category = Category.create!(name: "Netflix-99123", is_default: true, category_type: "expense")

    assert_not_equal ActivityClassification.normalize_name("Netflix-99123"), CategoryOption.new(category).search_text
    assert_equal "netflix 99123", CategoryOption.new(category).search_text
  end

  test "search_text is blank-safe for categories without a name" do
    assert_equal "", CategoryOption.new(Category.new).search_text
  end

  private

  def create_user
    User.create!(name: "Option User", email: "category_option_#{Time.now.to_i}@example.com", password: "password123")
  end
end
