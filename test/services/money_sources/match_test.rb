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

    def source_with_keywords(name:, keywords:, **opts)
      source = @user.money_sources.create!({ name: name, kind: "account", starting_balance: 0 }.merge(opts))
      source.ensure_recognition.replace_identifiers(keyword: keywords)
      source
    end

    test "returns nil when nothing matches" do
      assert_nil match(tag: "tarjeta clásica")
    end

    test "matches by recognition keyword when exactly one source has it" do
      source = source_with_keywords(name: "Visa", keywords: [ "tarjeta clásica" ])

      assert_equal source, match(tag: "Tarjeta Clásica")
    end

    test "normalizes keyword input" do
      source = source_with_keywords(name: "Visa", keywords: [ "tarjeta clásica" ])

      assert_equal source, match(tag: "  Tarjeta Clásica  ")
      assert_equal source, match(tag: "TARJETA CLÁSICA")
    end

    test "does not match keyword from different user" do
      other_source = @other_user.money_sources.create!(name: "Other Visa", kind: "credit_card")
      other_source.ensure_recognition.replace_identifiers(keyword: [ "tarjeta clásica" ])

      assert_nil match(tag: "tarjeta clásica")
    end

    test "does not match keyword from inactive source" do
      source = @user.money_sources.create!(name: "Old Card", kind: "credit_card")
      source.ensure_recognition.replace_identifiers(keyword: [ "tarjeta clásica" ])
      source.update!(active: false)

      assert_nil match(tag: "tarjeta clásica")
    end

    test "matches by source name" do
      source = @user.money_sources.create!(name: "Savings Bancolombia", kind: "account", starting_balance: 0)

      assert_equal source, match(tag: "savings bancolombia")
    end

    test "matches by card last four" do
      source = @user.money_sources.create!(name: "Visa", kind: "credit_card", identifier: "1234")

      assert_equal source, match(card_last_four: "1234")
    end

    test "card last four matches the source identifier ending digits" do
      source = @user.money_sources.create!(name: "Visa", kind: "credit_card", identifier: "987654321234")

      assert_equal source, match(card_last_four: "561234")
    end

    test "does not match card last four from inactive source" do
      source = @user.money_sources.create!(name: "Old Card", kind: "credit_card", identifier: "1234")
      source.update!(active: false)

      assert_nil match(card_last_four: "1234")
    end

    test "matches by bank institution" do
      source = @user.money_sources.create!(name: "Savings", kind: "account", bank: "Bancolombia", starting_balance: 0)

      assert_equal source, match(bank: "  BANCOLOMBIA  ")
    end

    test "does not match bank from different user" do
      @other_user.money_sources.create!(name: "Other Savings", kind: "account", bank: "Davivienda", starting_balance: 0)

      assert_nil match(bank: "Davivienda")
    end

    test "matches values across different sources (ambiguous)" do
      card_source = @user.money_sources.create!(name: "Visa", kind: "credit_card", identifier: "1234")
      bank_source = @user.money_sources.create!(name: "Savings", kind: "account", bank: "bancolombia", starting_balance: 0)

      result = match(card_last_four: "1234", bank: "bancolombia")
      assert_includes result, card_source
      assert_includes result, bank_source
    end

    test "returns multiple candidates when several sources match" do
      source_1 = source_with_keywords(name: "Source A", keywords: [ "tarjeta clásica" ])
      source_2 = source_with_keywords(name: "Source B", keywords: [ "tarjeta clásica" ])

      result = match(tag: "tarjeta clásica")
      assert_includes result, source_1
      assert_includes result, source_2
      assert_equal 2, result.length
    end

    test "returns only active sources" do
      inactive = @user.money_sources.create!(name: "Inactive", kind: "account", starting_balance: 0, active: false)
      inactive.ensure_recognition.replace_identifiers(keyword: [ "tarjeta clásica" ])
      active_source = source_with_keywords(name: "Active", keywords: [ "tarjeta clásica" ])

      assert_equal active_source, match(tag: "tarjeta clásica")
    end

    test "returns nil for non-existent value" do
      assert_nil match(tag: "non_existent")
    end
  end
end
