# frozen_string_literal: true

require "test_helper"

class MoneySourceIdentifierTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Test User", email: "identifier_test@example.com", password: "password123")
    @source = @user.money_sources.create!(name: "My Card", kind: "credit_card")
  end

  test "is valid with required attributes" do
    ident = MoneySourceIdentifier.new(money_source: @source, kind: "card_last_four", value: "1234")
    assert ident.valid?
  end

  test "kind is required and must be in KINDS" do
    ident = MoneySourceIdentifier.new(money_source: @source, value: "1234")
    assert_not ident.valid?
    assert_includes ident.errors[:kind], "can't be blank"

    ident.kind = "invalid"
    assert_not ident.valid?
    assert_includes ident.errors[:kind], "is not included in the list"
  end

  test "value is required" do
    ident = MoneySourceIdentifier.new(money_source: @source, kind: "card_last_four")
    assert_not ident.valid?
    assert_includes ident.errors[:value], "can't be blank"
  end

  test "value uniqueness scoped to kind" do
    MoneySourceIdentifier.create!(money_source: @source, kind: "card_last_four", value: "1234")
    duplicate = MoneySourceIdentifier.new(money_source: @source, kind: "card_last_four", value: "1234")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:value], "has already been taken"

    # Different kind allows same value
    other = MoneySourceIdentifier.new(money_source: @source, kind: "account_number", value: "1234")
    assert other.valid?
  end

  test "card_last_four normalizes to last 4 digits" do
    ident = MoneySourceIdentifier.create!(money_source: @source, kind: "card_last_four", value: "987654321")
    assert_equal "4321", ident.value
  end

  test "card_last_four strips non-digits" do
    ident = MoneySourceIdentifier.create!(money_source: @source, kind: "card_last_four", value: "AB-12-34")
    assert_equal "1234", ident.value
  end

  test "bank_name normalizes to downcased stripped" do
    ident = MoneySourceIdentifier.create!(money_source: @source, kind: "bank_name", value: "  Bancolombia  ")
    assert_equal "bancolombia", ident.value
  end

  test "account_number strips non-digits" do
    ident = MoneySourceIdentifier.create!(money_source: @source, kind: "account_number", value: "123-456-789")
    assert_equal "123456789", ident.value
  end

  test "by_kind scope filters correctly" do
    card_ident = MoneySourceIdentifier.create!(money_source: @source, kind: "card_last_four", value: "1111")
    bank_ident = MoneySourceIdentifier.create!(money_source: @source, kind: "bank_name", value: "bancolombia")
    assert_includes MoneySourceIdentifier.by_kind("card_last_four"), card_ident
    assert_not_includes MoneySourceIdentifier.by_kind("card_last_four"), bank_ident
  end

  test "parent money_source must be active" do
    inactive = @user.money_sources.create!(name: "Old Card", kind: "credit_card", active: false)
    ident = MoneySourceIdentifier.new(money_source: inactive, kind: "card_last_four", value: "5678")
    assert_not ident.valid?
    assert_includes ident.errors[:money_source], "must be active"
  end

  test "destroying money_source destroys identifiers" do
    @source.identifiers.create!(kind: "card_last_four", value: "1111")
    assert_difference "MoneySourceIdentifier.count", -1 do
      @source.destroy
    end
  end
end
