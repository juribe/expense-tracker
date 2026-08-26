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

    test "returns nil when no identifiers exist" do
      assert_nil match(card_last_four: "1234", bank: "Bancolombia")
    end

    test "matches by card_last_four when exactly one active source has that identifier" do
      source = @user.money_sources.create!(name: "Visa", kind: "credit_card")
      source.identifiers.create!(kind: "card_last_four", value: "1234")

      result = match(card_last_four: "1234")
      assert_equal source, result
    end

    test "normalizes card_last_four input" do
      source = @user.money_sources.create!(name: "Visa", kind: "credit_card")
      source.identifiers.create!(kind: "card_last_four", value: "1234")

      assert_equal source, match(card_last_four: "98761234")
      assert_equal source, match(card_last_four: "abcd-1234")
    end

    test "does not match card from different user" do
      other_source = @other_user.money_sources.create!(name: "Other Visa", kind: "credit_card")
      other_source.identifiers.create!(kind: "card_last_four", value: "5678")

      assert_nil match(card_last_four: "5678")
    end

    test "does not match inactive source by card" do
      source = @user.money_sources.create!(name: "Old Card", kind: "credit_card")
      source.identifiers.create!(kind: "card_last_four", value: "1234")
      source.update!(active: false)

      assert_nil match(card_last_four: "1234")
    end

    test "matches by bank_name when exactly one active source has that identifier" do
      source = @user.money_sources.create!(name: "Savings", kind: "account", bank: "bancolombia")
      source.identifiers.create!(kind: "bank_name", value: "bancolombia")

      result = match(bank: "Bancolombia")
      assert_equal source, result
    end

    test "normalizes bank name input" do
      source = @user.money_sources.create!(name: "Savings", kind: "account")
      source.identifiers.create!(kind: "bank_name", value: "bancolombia")

      assert_equal source, match(bank: "  Bancolombia  ")
      assert_equal source, match(bank: "BANCOLOMBIA")
    end

    test "does not match bank from different user" do
      other_source = @other_user.money_sources.create!(name: "Other Savings", kind: "account")
      other_source.identifiers.create!(kind: "bank_name", value: "davivienda")

      assert_nil match(bank: "Davivienda")
    end

    test "does not match inactive source by bank_name" do
      source = @user.money_sources.create!(name: "Old Account", kind: "account")
      source.identifiers.create!(kind: "bank_name", value: "bancolombia")
      source.update!(active: false)

      assert_nil match(bank: "Bancolombia")
    end

    test "prefers card match over bank match" do
      card_source = @user.money_sources.create!(name: "Visa", kind: "credit_card")
      card_source.identifiers.create!(kind: "card_last_four", value: "1234")

      bank_source = @user.money_sources.create!(name: "Savings", kind: "account")
      bank_source.identifiers.create!(kind: "bank_name", value: "bancolombia")

      result = match(card_last_four: "1234", bank: "Bancolombia")
      assert_equal card_source, result
    end

    test "falls back to bank match when card is nil" do
      bank_source = @user.money_sources.create!(name: "Savings", kind: "account")
      bank_source.identifiers.create!(kind: "bank_name", value: "bancolombia")

      result = match(bank: "Bancolombia")
      assert_equal bank_source, result
    end

    test "returns nil when both card and bank are blank" do
      assert_nil match
    end

    test "returns nil when card has no match and bank is nil" do
      source = @user.money_sources.create!(name: "Visa", kind: "credit_card")
      source.identifiers.create!(kind: "card_last_four", value: "1234")

      assert_nil match(card_last_four: "9999")
    end

    test "returns nil when card is nil and bank has no match" do
      source = @user.money_sources.create!(name: "Savings", kind: "account")
      source.identifiers.create!(kind: "bank_name", value: "bancolombia")

      assert_nil match(bank: "Davivienda")
    end
  end
end
