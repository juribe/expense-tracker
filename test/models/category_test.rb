# frozen_string_literal: true

require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  test "is valid with a name" do
    category = Category.new(name: "Food")
    assert category.valid?
  end

  test "name is required" do
    category = Category.new(name: "")
    assert_not category.valid?
    assert_includes category.errors[:name], "can't be blank"
  end

  test "name must be unique" do
    Category.create!(name: "Food")
    duplicate = Category.new(name: "Food")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "slug is auto-generated from name" do
    category = Category.create!(name: "Electronics & Gadgets")
    assert_equal "electronics-gadgets", category.slug
  end

  test "slug is regenerated when name changes" do
    category = Category.create!(name: "Electronics")
    assert_equal "electronics", category.slug
    category.update!(name: "Mobile Phones")
    assert_equal "mobile-phones", category.slug
  end

  test "active defaults to true" do
    category = Category.create!(name: "Food")
    assert category.active?
  end

  test "parent association supports nested categories" do
    parent = Category.create!(name: "Electronics")
    child = Category.create!(name: "Phones", parent: parent)
    assert_equal parent, child.parent
    assert_includes parent.children, child
  end

  test "parent cannot be the category itself" do
    category = Category.create!(name: "Food")
    category.parent = category
    assert_not category.valid?
    assert_includes category.errors[:parent_id], "can't be the category itself"
  end

  test "description is optional" do
    category = Category.new(name: "Food", description: nil)
    assert category.valid?
  end

  test "active scope returns only active categories" do
    active = Category.create!(name: "Active One")
    inactive = Category.create!(name: "Inactive One", active: false)
    assert_includes Category.active, active
    assert_not_includes Category.active, inactive
  end
end
