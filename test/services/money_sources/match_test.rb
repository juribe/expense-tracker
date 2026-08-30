# frozen_string_literal: true

require "test_helper"

module MoneySources
  class MatchTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Test User", email: "match_test@example.com", password: "password123")
      @other_user = User.create!(name: "Other", email: "match_other_test@example.com", password: "password123")
    end

    def match(**overrides)
      MoneySources::Match.call(user: @user, **overrides)
    end

    test "returns nil when no tags exist" do
      assert_nil match(tag: "tarjeta clásica")
    end

    test "matches by tag when exactly one active source has that tag" do
      source = @user.money_sources.create!(name: "Visa", kind: "credit_card")
      source.tags.create!(value: "tarjeta clásica")

      result = match(tag: "Tarjeta Clásica")
      assert_equal source, result
    end

    test "normalizes tag input" do
      source = @user.money_sources.create!(name: "Visa", kind: "credit_card")
      source.tags.create!(value: "tarjeta clásica")

      assert_equal source, match(tag: "  Tarjeta Clásica  ")
      assert_equal source, match(tag: "TARJETA CLÁSICA")
    end

    test "does not match tag from different user" do
      other_source = @other_user.money_sources.create!(name: "Other Visa", kind: "credit_card")
      other_source.tags.create!(value: "tarjeta clásica")

      assert_nil match(tag: "tarjeta clásica")
    end

    test "does not match tag from inactive source" do
      source = @user.money_sources.create!(name: "Old Card", kind: "credit_card")
      source.tags.create!(value: "tarjeta clásica")
      source.update!(active: false)

      assert_nil match(tag: "tarjeta clásica")
    end

    test "matches by tag for bank-like value" do
      source = @user.money_sources.create!(name: "Savings", kind: "account")
      source.tags.create!(value: "bancolombia")

      result = match(tag: "Bancolombia")
      assert_equal source, result
    end

    test "normalizes bank tag input" do
      source = @user.money_sources.create!(name: "Savings", kind: "account")
      source.tags.create!(value: "bancolombia")

      assert_equal source, match(tag: "  Bancolombia  ")
      assert_equal source, match(tag: "BANCOLOMBIA")
    end

    test "does not match bank tag from different user" do
      other_source = @other_user.money_sources.create!(name: "Other Savings", kind: "account")
      other_source.tags.create!(value: "davivienda")

      assert_nil match(tag: "Davivienda")
    end

    test "does not match inactive source by bank tag" do
      source = @user.money_sources.create!(name: "Old Account", kind: "account")
      source.tags.create!(value: "bancolombia")
      source.update!(active: false)

      assert_nil match(tag: "Bancolombia")
    end

    test "prefers tag match" do
      card_source = @user.money_sources.create!(name: "Visa", kind: "credit_card")
      card_source.tags.create!(value: "1234")

      bank_source = @user.money_sources.create!(name: "Savings", kind: "account")
      bank_source.tags.create!(value: "bancolombia")

      result = match(tag: "1234")
      assert_equal card_source, result
    end

    test "returns multiple candidates when multiple sources have same tag" do
      source_1 = @user.money_sources.create!(name: "Source A", kind: "account")
      source_1.tags.create!(value: "tarjeta clásica")

      source_2 = @user.money_sources.create!(name: "Source B", kind: "account")
      source_2.tags.create!(value: "tarjeta clásica")

      result = match(tag: "tarjeta clásica")
      assert_includes result, source_1
      assert_includes result, source_2
      assert_equal 2, result.length
    end

    test "returns only active sources when matching" do
      inactive = @user.money_sources.create!(name: "Inactive", kind: "account", active: false)
      active_source = @user.money_sources.create!(name: "Active", kind: "account")
      active_source.tags.create!(value: "tarjeta clásica")
      inactive.tags.create!(value: "tarjeta clásica")

      result = match(tag: "tarjeta clásica")
      assert_equal active_source, result
    end

    test "returns nil for non-existent tag" do
      assert_nil match(tag: "non_existent")
    end

    test "with_tag returns an empty relation for a non-existent tag" do
      assert_empty MoneySource.with_tag("non_existent")
    end

    test "with_tag scope works" do
      source = @user.money_sources.create!(name: "Visa", kind: "credit_card")
      source.tags.create!(value: "tarjeta clásica")

      result = MoneySource.with_tag("Tarjeta Clásica")
      assert_includes result, source
    end

    test "with_tag returns only active sources" do
      inactive = @user.money_sources.create!(name: "Inactive", kind: "account", active: false)
      active_source = @user.money_sources.create!(name: "Active", kind: "account")
      active_source.tags.create!(value: "tarjeta clásica")
      inactive.tags.create!(value: "tarjeta clásica")

      result = MoneySource.with_tag("tarjeta clásica")
      assert_includes result, active_source
      refute_includes result, inactive
    end
  end
end
