# frozen_string_literal: true

require "test_helper"

module SourceRecognition
  class SuggestionEngineTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(
        name: "Test User",
        email: "suggestion_engine_test@example.com",
        password: "password123"
      )
    end

    def create_source(name:, kind: "account", bank: nil, **opts)
      @user.money_sources.create!(
        { name: name, kind: kind, starting_balance: 0, bank: bank }.compact.merge(opts)
      )
    end

    def call(source)
      SourceRecognition::SuggestionEngine.new(source: source).call
    end

    def values(hash)
      hash.transform_values { |arr| arr.map { |s| s[:value] } }
    end

    test "first-time source gets keyword suggestions from its own name/bank" do
      source = create_source(name: "Cuenta de Ahorros Davibank", bank: "Davibank")
      result = call(source)

      assert_includes values(result)[:keywords], "davibank"
      assert_equal ["davibank.com"], values(result)[:senders]
      assert_empty result[:subjects]
    end

    test "suggests the last four digits first among keyword suggestions" do
      source = create_source(name: "Davibank Nómina", bank: "Davibank", identifier: "5678")
      keywords = call(source)[:keywords]

      assert_equal "5678", keywords.first[:value]
      assert_equal :last_four, keywords.first[:source]
      assert_includes keywords.map { |s| s[:value] }, "davibank"
    end

    test "last four suggestion re-derives only the ending digits" do
      source = create_source(name: "Davibank Nómina", bank: "Davibank", identifier: "9999")
      source.update_columns(identifier: "12345678")
      keywords = call(source)[:keywords]

      assert_equal "5678", keywords.first[:value]
      assert_equal :last_four, keywords.first[:source]
    end

    test "no last four suggestion with fewer than four digits" do
      source = create_source(name: "Dinero en mano", kind: "cash", bank: nil, identifier: "12")
      keywords = call(source)[:keywords]

      assert_empty keywords.select { |s| s[:source] == :last_four }
    end

    test "last four suggestion excluded when already configured" do
      source = create_source(name: "Davibank Nómina", bank: "Davibank", identifier: "5678")
      source.ensure_recognition.replace_identifiers(keyword: ["5678"])

      assert_empty call(source)[:keywords].select { |s| s[:source] == :last_four }
    end

    test "blank bank produces no sibling-based suggestions" do
      source = create_source(name: "Dinero en mano", bank: nil)
      result = call(source)
      assert_empty result[:senders]
      assert_empty result[:subjects]
    end

    test "suggests the bank domain when no sibling of the institution is configured" do
      source = create_source(name: "Davibank Nómina", bank: "Davibank")
      senders = call(source)[:senders]

      assert_equal ["davibank.com"], senders.map { |s| s[:value] }
      assert_equal [:institution], senders.map { |s| s[:source] }
    end

    test "multi-token banks produce no domain guess" do
      source = create_source(name: "Cuenta Ahorros", bank: "Banco de Bogotá")
      assert_empty call(source)[:senders]
    end

    test "bank domain guess is excluded when already configured" do
      source = create_source(name: "Davibank Nómina", bank: "Davibank")
      source.ensure_recognition.replace_identifiers(domain: ["davibank.com"])
      assert_empty call(source)[:senders]
    end

    test "reuses sibling senders and subjects with the sibling as provenance" do
      sibling = create_source(name: "Davibank Clásica", bank: "davibank")
      sibling.ensure_recognition.replace_identifiers(
        sender: ["no-reply@davibank.com"], domain: ["davibank.com"],
        subject: ["Movimiento de dinero"], header: ["X-Banco: Davibank"]
      )

      source = create_source(name: "Davibank Nómina", bank: "davibank")
      result = call(source)

      assert_equal ["davibank.com", "no-reply@davibank.com"],
                   values(result)[:senders].sort
      assert_equal ["Movimiento de dinero", "X-Banco: Davibank"],
                   values(result)[:subjects].sort
      assert_equal ["Davibank Clásica"], result[:senders].map { |s| s[:source] }.uniq
      assert_equal ["Davibank Clásica"], result[:subjects].map { |s| s[:source] }.uniq
    end

    test "matches siblings regardless of bank casing or padding" do
      sibling = create_source(name: "Davibank Clásica", bank: "Davibank ")
      sibling.ensure_recognition.replace_identifiers(sender: ["no-reply@davibank.com"])

      source = create_source(name: "Davibank Nómina", bank: "davibank")
      result = call(source)

      assert_includes values(result)[:senders], "no-reply@davibank.com"
      assert_equal ["Davibank Clásica"], result[:senders].map { |s| s[:source] }.uniq
    end

    test "same email configured on several siblings is suggested only once" do
      sibling_a = create_source(name: "Davibank Clásica", bank: "davibank")
      sibling_a.ensure_recognition.replace_identifiers(sender: ["no-reply@davibank.com"], subject: ["Movimiento"])
      sibling_b = create_source(name: "Davibank Oro", bank: "davibank")
      sibling_b.ensure_recognition.replace_identifiers(sender: ["no-reply@davibank.com"], subject: ["Movimiento"])

      source = create_source(name: "Davibank Nómina", bank: "davibank")
      result = call(source)

      assert_equal 1, result[:senders].length
      assert_equal 1, result[:subjects].length
    end

    test "same email with different casing is suggested only once" do
      sibling_a = create_source(name: "Davibank Clásica", bank: "davibank")
      sibling_a.ensure_recognition.replace_identifiers(sender: ["no-reply@davibank.com"])
      sibling_b = create_source(name: "Davibank Oro", bank: "davibank")
      sibling_b.ensure_recognition.replace_identifiers(sender: ["No-Reply@Davibank.com"])

      source = create_source(name: "Davibank Nómina", bank: "davibank")
      assert_equal 1, call(source)[:senders].length
    end

    test "institution token colliding with a name token is suggested only once" do
      sibling = create_source(name: "Davibank Clásica", bank: "davibank")
      sibling.ensure_recognition.replace_identifiers(sender: ["x@davibank.com"])

      source = create_source(name: "Davibank Nómina", bank: "davibank")
      keywords = call(source)[:keywords]

      assert_equal 1, keywords.count { |s| s[:value] == "davibank" }
    end

    test "never copies a sibling product-specific keyword" do
      sibling = create_source(name: "Davibank Clásica", bank: "davibank")
      sibling.ensure_recognition.replace_identifiers(keyword: ["clasica", "davibank"])

      source = create_source(name: "Davibank Nómina", bank: "davibank")
      result = call(source)

      keywords = values(result)[:keywords]
      assert_includes keywords, "davibank"
      assert_not_includes keywords, "clasica"
    end

    test "suggests the institution token as a keyword only when siblings exist" do
      source = create_source(name: "Davibank Nómina", bank: "davibank")
      # Name-derived token exists, but no institution-sourced one without siblings.
      assert_empty call(source)[:keywords].select { |s| s[:source] == :institution }

      sibling = create_source(name: "Davibank Clásica", bank: "davibank")
      sibling.ensure_recognition.replace_identifiers(sender: ["x@davibank.com"])
      keywords = call(source)[:keywords]
      assert_includes keywords.map { |s| s[:value] }, "davibank"
      # Suggested exactly once, no duplicate from the institution path.
      assert_equal 1, keywords.count { |s| s[:value] == "davibank" }
    end

    test "excludes values already configured on the current source" do
      sibling = create_source(name: "Davibank Clásica", bank: "davibank")
      sibling.ensure_recognition.replace_identifiers(sender: ["no-reply@davibank.com"])

      source = create_source(name: "Davibank Nómina", bank: "davibank")
      source.ensure_recognition.replace_identifiers(
        sender: ["no-reply@davibank.com"], domain: ["davibank.com"]
      )

      assert_empty call(source)[:senders]
    end

    test "does not persist anything" do
      sibling = create_source(name: "Davibank Clásica", bank: "davibank")
      sibling.ensure_recognition.replace_identifiers(sender: ["x@davibank.com"])
      source = create_source(name: "Davibank Nómina", bank: "davibank")

      call(source)

      source.reload
      assert_not source.recognition_configured?
    end
  end
end
