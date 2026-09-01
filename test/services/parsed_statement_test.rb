# frozen_string_literal: true

require "test_helper"

class ParsedStatementTest < ActiveSupport::TestCase
  test "maps attributes and converts money fields to decimals" do
    statement = ParsedStatement.new(
      kind: "credit_card", name: "Visa", bank: "Bancolombia",
      card_last_four: "1234", balance: "5420000", credit_limit: "10000000",
      interest_rate: "24.5"
    )
    assert_equal "credit_card", statement.kind
    assert_equal BigDecimal("5420000"), statement.balance
    assert_equal BigDecimal("10000000"), statement.credit_limit
    assert_equal BigDecimal("24.5"), statement.interest_rate
  end

  test "ignores unparseable amounts" do
    statement = ParsedStatement.new(balance: "abc", credit_limit: nil)
    assert_nil statement.balance
    assert_nil statement.credit_limit
  end

  test "serializes to a plain hash with string keys" do
    statement = ParsedStatement.new(kind: "account", name: "Savings", bank: "Bancolombia", balance: "100")
    hash = statement.to_h
    assert_equal "account", hash["kind"]
    assert_equal BigDecimal("100"), hash["balance"]
    assert_nil hash["transactions"] if hash.key?("transactions")
  end

  test "display_name shows masked last four when present" do
    statement = ParsedStatement.new(name: "Bancolombia", bank: "Bancolombia", card_last_four: "1234")
    assert_equal "Bancolombia ••••1234", statement.display_name
  end

  test "display_name falls back to the bank" do
    statement = ParsedStatement.new(bank: "Davivienda")
    assert_equal "Davivienda", statement.display_name
  end
end
