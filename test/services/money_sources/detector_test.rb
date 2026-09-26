# frozen_string_literal: true

require "test_helper"

# MoneySources::Detector: registered-source matching against a text slice,
# plus the generic payment-vocabulary check used to block cross-expense
# source inheritance.
class MoneySourcesDetectorTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Detector User", email: "detector@example.com", password: "password123")
    @nequi = @user.money_sources.create!(name: "Nequi", kind: "wallet")
    @nequi.ensure_recognition.replace_identifiers(keyword: [ "nequi" ])
    @efectivo = @user.money_sources.create!(name: "Efectivo", kind: "cash")
    @efectivo.ensure_recognition.replace_identifiers(keyword: [ "efectivo" ])
  end

  def detector
    MoneySources::Detector.new(user: @user)
  end

  test "call returns the first matching registered source" do
    assert_equal @nequi, detector.call("gasté 50 mil desde nequi")
  end

  test "matching_sources returns every matching registered source" do
    matches = detector.matching_sources("50 con nequi y 25 en efectivo")

    assert_equal [ @nequi, @efectivo ], matches
  end

  test "matching_sources is empty for unregistered payment mentions" do
    assert_empty detector.matching_sources("80.000 del supermercado con tarjeta Infinite")
  end

  test "payment_mention? detects generic payment vocabulary" do
    assert MoneySources::Detector.payment_mention?("80.000 del supermercado con tarjeta Infinite")
    assert MoneySources::Detector.payment_mention?("pagué 50.000 en EFECTIVO")
    assert MoneySources::Detector.payment_mention?("transferencia a Juan")
  end

  test "payment_mention? ignores non-payment uses" do
    refute MoneySources::Detector.payment_mention?("gasté 50 mil en almuerzo con amigos")
    refute MoneySources::Detector.payment_mention?("")
  end

  test "payment_mention? does not match derived words" do
    refute MoneySources::Detector.payment_mention?("efectivamente hablando")
  end

  test "scored_matches weighs identifiers over the bank" do
    davibank = @user.money_sources.create!(name: "Cuenta Davibank", kind: "account", bank: "Davibank")
    davibank.ensure_recognition.replace_identifiers(keyword: [ "davibank" ])

    matches = detector.scored_matches("500.000 de cuenta davibank a Nequi")

    scored = matches.to_h { |source, score| [ source.name, score ] }
    # name (2) + keyword "davibank" (2) + bank (1)
    assert_equal 5, scored["Cuenta Davibank"]
    # name and keyword "nequi" collapse to one matched value
    assert_equal 2, scored["Nequi"]
  end

  test "a bank-only match scores below a keyword match" do
    @user.money_sources.create!(name: "Cuenta de Ahorros", kind: "account", bank: "Davibank")
    davibank = @user.money_sources.create!(name: "Cuenta Davibank", kind: "account", bank: "Davibank")
    davibank.ensure_recognition.replace_identifiers(keyword: [ "davibank" ])

    assert_equal davibank, detector.best_match("pagué en davibank")&.first
  end

  test "best_match prefers the source with more matched values" do
    @user.money_sources.create!(name: "Otra Cuenta", kind: "account", bank: "Davibank")
    davibank = @user.money_sources.create!(name: "Cuenta Davibank", kind: "account", bank: "Davibank")
    davibank.ensure_recognition.replace_identifiers(keyword: [ "davibank" ])

    assert_equal davibank, detector.best_match("500.000 de cuenta davibank")&.first
  end

  test "best_match keeps the first-loaded source on a tie" do
    first = @user.money_sources.create!(name: "Banco Uno", kind: "account", bank: "Davibank")
    @user.money_sources.create!(name: "Banco Dos", kind: "account", bank: "Davibank")

    assert_equal first, detector.best_match("pagué en davibank")&.first
  end

  test "grounded_in? is true when the fragment names the identifier" do
    davibank = @user.money_sources.create!(name: "Cuenta Davibank", kind: "account", bank: "Davibank")
    davibank.ensure_recognition.replace_identifiers(keyword: [ "cuenta davibank" ])

    assert detector.grounded_in?(davibank, "45.000 con la cuenta de Davibank")
    assert detector.grounded_in?(davibank, "45.000 con la cuenta davibank")
  end

  test "grounded_in? is false for a bank-level-only mention" do
    davibank = @user.money_sources.create!(name: "Cuenta Davibank", kind: "account", bank: "Davibank")
    davibank.ensure_recognition.replace_identifiers(keyword: [ "cuenta davibank" ])

    refute detector.grounded_in?(davibank, "45.000 con Davibank")
  end

  test "grounded_in? handles single-word and numeric identifiers" do
    tarjeta = @user.money_sources.create!(name: "tarjeta davibank", kind: "credit_card", bank: "Davibank")
    tarjeta.ensure_recognition.replace_identifiers(keyword: [ "tarjeta davibank", "tarjeta" ])

    assert detector.grounded_in?(tarjeta, "45.000 con la tarjeta")
    assert detector.grounded_in?(tarjeta, "45.000 con la tarjeta de crédito davibank")
    refute detector.grounded_in?(tarjeta, "45.000 con Davibank")
  end

  test "grounded_in? is false without the source's words" do
    davibank = @user.money_sources.create!(name: "Cuenta Davibank", kind: "account", bank: "Davibank")
    davibank.ensure_recognition.replace_identifiers(keyword: [ "cuenta davibank" ])

    refute detector.grounded_in?(davibank, "45.000 en almuerzo")
    refute detector.grounded_in?(davibank, "")
  end
end
