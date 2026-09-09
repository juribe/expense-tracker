# frozen_string_literal: true

require "test_helper"

class ExpenseCandidateTest < ActiveSupport::TestCase
  def valid_candidate
    ExpenseCandidate.new(
      amount: 50_000,
      currency: "COP",
      category_id: 12,
      category_name: "Food",
      description: "almuerzos",
      merchant: nil,
      date: Date.current,
      source: "text",
      confidence: 0.94
    )
  end

  test "is valid with amount, category and date" do
    candidate = valid_candidate
    assert candidate.valid?
    assert_empty candidate.errors
  end

  test "defaults currency to COP and source to playground" do
    candidate = ExpenseCandidate.new(amount: 100, category_name: "Food", date: Date.current)
    assert_equal "COP", candidate.currency
    assert_equal "playground", candidate.source
  end

  test "clamps confidence between 0 and 1" do
    assert_equal 1.0, ExpenseCandidate.new(confidence: 1.5).confidence
    assert_equal 0.0, ExpenseCandidate.new(confidence: -0.2).confidence
    assert_nil ExpenseCandidate.new(confidence: "not-a-number").confidence
  end

  test "is invalid without a positive amount" do
    assert ExpenseCandidate.new(category_name: "Food", date: Date.current).invalid?
    assert ExpenseCandidate.new(amount: 0, category_name: "Food", date: Date.current).invalid?
    assert ExpenseCandidate.new(amount: -5, category_name: "Food", date: Date.current).invalid?
    assert ExpenseCandidate.new(amount: BigDecimal("100000000"), category_name: "Food", date: Date.current).invalid?
  end

  test "is invalid without a category id or name" do
    candidate = ExpenseCandidate.new(amount: 100, date: Date.current)
    assert candidate.invalid?
    assert candidate.errors.any? { |message| message.include?("category") }
  end

  test "is invalid without a date" do
    assert ExpenseCandidate.new(amount: 100, category_name: "Food").invalid?
  end

  test "is valid with only a category name" do
    candidate = ExpenseCandidate.new(amount: 100, category_name: "Groceries", date: Date.current)
    assert candidate.valid?
  end

  test "checks reflect the candidate state" do
    checks = valid_candidate.checks.index_by { |check| check[:label] }
    assert checks.values.all? { |check| check[:passed] }

    empty = ExpenseCandidate.new
    failed = empty.checks.index_by { |check| check[:label] }
    assert_not failed["Amount present"][:passed]
    assert_not failed["Category mapped"][:passed]
    assert_not failed["Valid date"][:passed]
  end

  test "from_h parses string params from the API" do
    candidate = ExpenseCandidate.from_h(
      "amount" => "50,000",
      "currency" => "COP",
      "category_id" => "12",
      "description" => "Almuerzos",
      "merchant" => "",
      "date" => Date.current.iso8601,
      "confidence" => "0.9"
    )

    assert_equal BigDecimal(50_000.to_s), candidate.amount
    assert_equal 12, candidate.category_id
    assert_equal Date.current, candidate.date
    assert_in_delta 0.9, candidate.confidence, 0.001
  end

  test "from_h survives garbage input" do
    candidate = ExpenseCandidate.from_h(
      "amount" => "abc",
      "category_id" => "",
      "date" => "not a date"
    )
    assert candidate.invalid?
    assert_nil candidate.amount
    assert_nil candidate.date
  end

  test "as_json serializes the date to iso8601" do
    payload = valid_candidate.as_json
    assert_equal Date.current.iso8601, payload[:date]
    assert_equal "text", payload[:source]
  end
end
