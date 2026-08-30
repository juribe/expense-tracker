# frozen_string_literal: true

require "test_helper"

class MoneySourceTagTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Test User", email: "tag_test@example.com", password: "password123")
    @source = @user.money_sources.create!(name: "Test Source", identifier: "test_identifier_123", kind: "account")
  end

  test "requires a money source" do
    tag = MoneySourceTag.new(value: "tarjeta clásica")
    assert_not tag.valid?
    assert tag.errors[:money_source].any?
  end

  test "requires a value" do
    tag = MoneySourceTag.new(money_source: @source)
    assert_not tag.valid?
    assert tag.errors[:value].any?
  end

  test "normalizes whitespace on create" do
    tag = MoneySourceTag.create!(money_source: @source, value: "  tag value  ")
    assert_equal "tag value", tag.value
  end

  test "normalizes case on create" do
    tag = MoneySourceTag.create!(money_source: @source, value: "TARGA CLÁSICA")
    assert_equal "targa clásica", tag.value
  end

  test "tag value saved stripped and downcased" do
    tag = @source.tags.create!(value: "  TARJETA CLÁSICA  ")
    assert_equal "tarjeta clásica", tag.value
  end

  test "multiple tags can belong to same source" do
    @source.tags.create!(value: "tarjeta clásica")
    @source.tags.create!(value: "tarjeta clasica")
    @source.tags.create!(value: "visa clásica")
    assert_equal 3, @source.tags.count
  end

  test "prevents duplicate normalized tags on the same source" do
    @source.tags.create!(value: "tarjeta clásica")
    duplicate = @source.tags.build(value: "  TARJETA CLÁSICA  ")
    assert_not duplicate.valid?
    assert duplicate.errors[:value].any?
  end

  test "allows the same tag on different MoneySources" do
    other = @user.money_sources.create!(name: "Other", identifier: "other_id", kind: "account")
    tag1 = @source.tags.create!(value: "tag value")
    tag2 = other.tags.create!(value: "tag value")
    assert_predicate tag1, :persisted?
    assert_predicate tag2, :persisted?
  end

  test "matching finds source by tag" do
    @source.tags.create!(value: "tarjeta clásica")
    result = MoneySourceTag.matching("Tarjeta Clásica")
    assert_includes result, @source
  end

  test "matching is case and whitespace insensitive" do
    @source.tags.create!(value: "tarjeta clásica")
    assert_includes MoneySourceTag.matching("TARJETA CLÁSICA"), @source
    assert_includes MoneySourceTag.matching("  tarjeta clásica  "), @source
  end

  test "matching returns multiple candidates" do
    other = @user.money_sources.create!(name: "Other", identifier: "other_id", kind: "account")
    @source.tags.create!(value: "tarjeta clásica")
    other.tags.create!(value: "tarjeta clásica")
    result = MoneySourceTag.matching("tarjeta clásica")
    assert_includes result, @source
    assert_includes result, other
    assert_equal 2, result.length
  end

  test "matching returns only active sources" do
    inactive = @user.money_sources.create!(name: "Inactive", identifier: "inactive_id", kind: "account", active: false)
    @source.tags.create!(value: "tarjeta clásica")
    inactive.tags.create!(value: "tarjeta clásica")
    result = MoneySourceTag.matching("tarjeta clásica")
    assert_includes result, @source
    refute_includes result, inactive
  end

  test "matching returns empty for non-existent tag" do
    assert_empty MoneySourceTag.matching("non_existent")
  end
end
