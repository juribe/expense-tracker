# frozen_string_literal: true

require "test_helper"

class StatementDuplicateDetectorTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Test User", email: "dup_detector_test@example.com", password: "password123")
    @detector = StatementDuplicateDetector.new(user: @user)
  end

  def create_source(**overrides)
    @user.money_sources.create!(
      { name: "Source", kind: "account", starting_balance: 0 }.merge(overrides)
    )
  end

  def statement(overrides = {})
    ParsedStatement.new(
      { kind: "credit_card", name: "Visa", bank: "Bancolombia", card_last_four: "1234" }.merge(overrides)
    )
  end

  test "matches an existing source by identifier" do
    existing = create_source(name: "Bancolombia Visa", kind: "credit_card", bank: "Bancolombia", identifier: "1234")
    assert_equal existing, @detector.duplicate_of?(statement(identifier: "1234"))
  end

  test "identifier matching is case and whitespace insensitive" do
    existing = create_source(name: "Bancolombia Visa", kind: "credit_card", bank: "Bancolombia", identifier: "  ABCD ")
    found = @detector.duplicate_of?(statement(identifier: "abcd"))
    assert_equal existing, found
  end

  test "matches by bank and card last four" do
    existing = create_source(name: "Visa", kind: "credit_card", bank: "Bancolombia")
    existing.build_credit_account(card_last_four: "1234")
    existing.save!
    assert_equal existing, @detector.duplicate_of?(statement)
  end

  test "returns nil when there is no match" do
    assert_nil @detector.duplicate_of?(statement)
  end

  test "ignores statements without any matching information" do
    assert_nil @detector.duplicate_of?(statement(bank: nil, card_last_four: nil))
  end
end
