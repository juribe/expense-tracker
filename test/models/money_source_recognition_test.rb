# frozen_string_literal: true

require "test_helper"

class MoneySourceRecognitionTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Test User", email: "recognition_test@example.com", password: "password123")
  end

  def create_source(**overrides)
    @user.money_sources.create!(
      { name: "Davibank", kind: "account", starting_balance: 0, bank: "Davibank" }.merge(overrides)
    )
  end

  test "configured? is true only when it has at least one identifier" do
    recognition = create_source.ensure_recognition
    assert_not recognition.configured?
    recognition.replace_identifiers(keyword: ["davi"])
    assert recognition.configured?
  end

  test "recognition_configured? reflects any identifier on the source" do
    source = create_source
    assert_not source.recognition_configured?
    source.ensure_recognition.replace_identifiers(sender: ["no-reply@davibank.com"])
    assert source.recognition_configured?
  end

  test "replace_identifiers adds and removes per kind (full replace)" do
    source = create_source
    source.ensure_recognition.replace_identifiers(keyword: %w[davi origen], sender: ["a@x.com"])
    ids = source.recognition.recognition_identifiers
    assert_equal %w[davi origen], ids.select(&:keyword?).map(&:value).sort
    assert_equal ["a@x.com"], ids.select(&:sender?).map(&:value)

    source.ensure_recognition.replace_identifiers(keyword: ["origen"], sender: [], subject: ["Movimiento"])
    ids = source.recognition.recognition_identifiers
    assert_equal ["origen"], ids.select(&:keyword?).map(&:value)
    assert_empty ids.select(&:sender?)
    assert_equal ["Movimiento"], ids.select(&:subject?).map(&:value)
  end

  test "replace_identifiers normalizes and de-duplicates values" do
    source = create_source
    source.ensure_recognition.replace_identifiers(keyword: ["  davi ", "davi"])
    assert_equal ["davi"], source.recognition.recognition_identifiers.select(&:keyword?).map(&:value)
  end

  test "replace_identifiers with all-empty values leaves nothing configured" do
    source = create_source
    source.ensure_recognition.replace_identifiers(keyword: ["davi"])
    source.ensure_recognition.replace_identifiers(keyword: [])
    assert_not source.recognition_configured?
    assert_empty source.recognition.recognition_identifiers
  end

  test "replace_identifiers does not touch persisted suggestions" do
    source = create_source
    recognition = source.ensure_recognition.tap(&:save!)
    suggestion = recognition.recognition_identifiers.create!(
      kind: "sender", value: "descubierto@davibank.com", status: "suggested", origin: "gmail"
    )

    recognition.replace_identifiers(keyword: ["davi"])
    recognition.reload

    assert suggestion.reload.persisted?
    assert suggestion.suggested?
    assert source.recognition_identifiers.where(kind: "keyword", status: "confirmed").exists?
  end

  test "accepting a suggestion promotes it to confirmed without duplicating it" do
    source = create_source
    recognition = source.ensure_recognition.tap(&:save!)
    recognition.recognition_identifiers.create!(
      kind: "sender", value: "descubierto@davibank.com", status: "suggested", origin: "gmail", observation_count: 3
    )

    recognition.replace_identifiers(sender: ["descubierto@davibank.com"])

    identifiers = source.recognition_identifiers.where(kind: "sender")
    assert_equal 1, identifiers.count
    assert identifiers.first.confirmed?
    assert_equal "user", identifiers.first.origin
  end

  test "dismiss_suggestions! removes only the dismissed suggested values" do
    source = create_source
    recognition = source.ensure_recognition.tap(&:save!)
    recognition.recognition_identifiers.create!(kind: "sender", value: "a@davibank.com", status: "suggested", origin: "gmail")
    recognition.recognition_identifiers.create!(kind: "domain", value: "davibank.com", status: "suggested", origin: "gmail")
    recognition.replace_identifiers(keyword: ["davi"])

    recognition.dismiss_suggestions!("senders" => ["a@davibank.com"])

    assert_nil recognition.recognition_identifiers.find_by(kind: "sender", value: "a@davibank.com")
    assert recognition.recognition_identifiers.exists?(kind: "domain", value: "davibank.com")
    assert recognition.recognition_identifiers.exists?(kind: "keyword", value: "davi")
  end

  test "configured? requires a confirmed identifier" do
    source = create_source
    recognition = source.ensure_recognition.tap(&:save!)
    recognition.recognition_identifiers.create!(
      kind: "sender", value: "descubierto@davibank.com", status: "suggested", origin: "gmail"
    )

    assert_not recognition.configured?
    assert_not source.recognition_configured?
  end

  test "new identifiers default to confirmed/user status" do
    source = create_source
    recognition = source.ensure_recognition.tap(&:save!)
    identifier = recognition.recognition_identifiers.create!(kind: "keyword", value: "davi")

    assert identifier.confirmed?
    assert_equal "user", identifier.origin
    assert_equal 1, identifier.observation_count
  end

  test "destroying recognition destroys its identifiers but keeps the source" do
    source = create_source
    source.ensure_recognition.replace_identifiers(keyword: ["davi"])
    recognition_id = source.recognition.id

    source.recognition.destroy

    assert_equal 0, MoneySourceRecognitionIdentifier.where(money_source_recognition_id: recognition_id).count
    source.reload
    assert source.persisted?
    assert_nil source.recognition
  end

  test "identifier kind must be one of KINDS" do
    source = create_source
    recognition = source.ensure_recognition.tap(&:save!)
    recognition.recognition_identifiers.build(kind: "bogus", value: "x")
    assert_not recognition.valid?
  end

  test "identifier value is unique per kind within a recognition" do
    source = create_source
    recognition = source.ensure_recognition.tap(&:save!)
    recognition.replace_identifiers(keyword: ["davi"])
    recognition.recognition_identifiers.build(kind: "keyword", value: "davi")
    assert_not recognition.valid?
  end
end
