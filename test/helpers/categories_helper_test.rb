# frozen_string_literal: true

require "test_helper"

class CategoriesHelperTest < ActionView::TestCase
  tests CategoriesHelper

  test "category_icon_klass returns the stored icon when valid" do
    category = Category.new(name: "Food", icon: "ti-star")
    assert_equal "ti ti-star", category_icon_klass(category)
  end

  test "category_icon_klass falls back to ti-tag when icon is nil" do
    category = Category.new(name: "Food", icon: nil)
    assert_equal "ti ti-tag", category_icon_klass(category)
  end

  test "category_icon_klass falls back to ti-tag when icon is blank" do
    category = Category.new(name: "Food", icon: "   ")
    assert_equal "ti ti-tag", category_icon_klass(category)
  end

  test "category_icon_klass falls back to ti-tag when icon is malformed" do
    category = Category.new(name: "Food", icon: "not-a-ti-icon")
    assert_equal "ti ti-tag", category_icon_klass(category)
  end

  test "category_icon_klass handles a nil category" do
    assert_equal "ti ti-tag", category_icon_klass(nil)
  end

  test "category_icon renders an i tag with the resolved class" do
    category = Category.new(name: "Food", icon: "ti-star")
    html = category_icon(category)
    assert_includes html, 'class="ti ti-star"'
    assert_includes html, 'aria-hidden="true"'
  end

  test "category_accent returns a stable palette token" do
    category = Category.new(id: "11111111-1111-1111-1111-111111111111")

    assert_includes CategoriesHelper::ACCENTS, category_accent(category)
    assert_equal category_accent(category), category_accent(category)
  end

  test "category_accent falls back to the first palette token without an id" do
    assert_equal "primary", category_accent(Category.new)
  end
end
