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

  # --- Default vs Custom ---

  test "default scope returns only default categories" do
    default_cat = Category.create!(name: "Default Cat", is_default: true, category_type: "expense")
    custom_cat = Category.create!(name: "Custom Cat", is_default: false, category_type: "expense")
    assert_includes Category.defaults, default_cat
    assert_not_includes Category.defaults, custom_cat
  end

  test "for_user returns defaults and user's custom categories" do
    user = User.create!(name: "Test", email: "scope_test_#{Time.now.to_i}@example.com", password: "password123")
    default_cat = Category.create!(name: "Default Cat", is_default: true, category_type: "expense")
    custom_cat = Category.create!(name: "Custom Cat", is_default: false, category_type: "expense", user: user)
    other_user = User.create!(name: "Other", email: "other_#{Time.now.to_i}@example.com", password: "password123")
    other_custom = Category.create!(name: "Other Cat", is_default: false, category_type: "expense", user: other_user)

    visible = Category.for_user(user)
    assert_includes visible, default_cat
    assert_includes visible, custom_cat
    assert_not_includes visible, other_custom
  end

  test "default? returns true for default categories" do
    cat = Category.create!(name: "Salary", is_default: true, category_type: "income")
    assert cat.default?
    assert_not cat.custom?
  end

  test "custom? returns true for custom categories" do
    user = User.create!(name: "Test", email: "custom_test_#{Time.now.to_i}@example.com", password: "password123")
    cat = Category.create!(name: "Crypto", is_default: false, category_type: "expense", user: user)
    assert cat.custom?
    assert_not cat.default?
  end

  test "editable_by returns true only for custom categories owned by user" do
    user = User.create!(name: "Test", email: "edit_test_#{Time.now.to_i}@example.com", password: "password123")
    custom = Category.create!(name: "My Cat", is_default: false, category_type: "expense", user: user)
    default_cat = Category.create!(name: "Default Cat", is_default: true, category_type: "expense")
    other_user = User.create!(name: "Other", email: "other_edit_#{Time.now.to_i}@example.com", password: "password123")

    assert custom.editable_by?(user)
    assert_not default_cat.editable_by?(user)
    assert_not custom.editable_by?(other_user)
  end

  test "default categories cannot have a user_id" do
    user = User.create!(name: "Test", email: "default_user_#{Time.now.to_i}@example.com", password: "password123")
    cat = Category.new(name: "Locked", is_default: true, category_type: "expense", user: user)
    assert_not cat.valid?
    assert_includes cat.errors[:user_id], "can't be set on default categories"
  end

  test "custom category cannot have same name as default of same type" do
    Category.create!(name: "Food & Dining", is_default: true, category_type: "expense")
    user = User.create!(name: "Test", email: "dup_default_#{Time.now.to_i}@example.com", password: "password123")
    cat = Category.new(name: "Food & Dining", is_default: false, category_type: "expense", user: user)
    assert_not cat.valid?
    assert_includes cat.errors[:name], "is already a default category for this type"
  end

  test "custom category uniqueness per user and type" do
    user = User.create!(name: "Test", email: "uniq_test_#{Time.now.to_i}@example.com", password: "password123")
    Category.create!(name: "Crypto", is_default: false, category_type: "expense", user: user)
    duplicate = Category.new(name: "Crypto", is_default: false, category_type: "expense", user: user)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken for this category type"
  end

  test "different users can have same custom category name" do
    user1 = User.create!(name: "User 1", email: "du1_#{Time.now.to_i}@example.com", password: "password123")
    user2 = User.create!(name: "User 2", email: "du2_#{Time.now.to_i}@example.com", password: "password123")
    Category.create!(name: "Crypto", is_default: false, category_type: "expense", user: user1)
    cat2 = Category.new(name: "Crypto", is_default: false, category_type: "expense", user: user2)
    assert cat2.valid?
  end

  test "category_type validates inclusion" do
    cat = Category.new(name: "Test", category_type: "invalid")
    assert_not cat.valid?
    assert_includes cat.errors[:category_type], "is not included in the list"
  end

  test "category_type can be nil" do
    cat = Category.new(name: "Test", category_type: nil)
    assert cat.valid?
  end
end
