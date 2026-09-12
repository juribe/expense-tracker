# frozen_string_literal: true

require "test_helper"

class ExpensePlaygroundEvaluationsComparatorTest < ActiveSupport::TestCase
  def call(expected:, actual:)
    ExpensePlayground::Evaluations::Comparator.call(expected: expected, actual: actual)
  end

  def expected_json
    {
      "intent" => "expense",
      "amount" => 20_000,
      "date" => "2026-09-12",
      "activity" => "almuerzo",
      "category" => "Comida",
      "subcategory" => "Almuerzos",
      "money_source" => "Nequi",
      "currency" => "COP"
    }
  end

  test "a result matching every expected field is a full match" do
    result = call(expected: expected_json, actual: expected_json)

    assert_equal true, result[:valid]
    assert_equal true, result[:full_match]
    assert result[:fields].values.all? { |field| field[:compared] && field[:matched] }
  end

  test "amounts are normalized across numeric/string/currency formats" do
    expected = expected_json

    [ 20_000, "20000", "20.000", "20,000" ].each do |amount|
      actual = expected_json.merge("amount" => amount)
      result = call(expected: expected, actual: actual)
      assert result[:full_match], "amount #{amount.inspect} should match"
    end
  end

  test "dates are canonical regardless of input format" do
    result = call(expected: expected_json, actual: expected_json.merge("date" => "09/09/2026"))
    assert_not result[:full_match], "a different date must not match"

    match = call(expected: expected_json, actual: expected_json.merge("date" => "2026/09/12"))
    assert match[:full_match]
  end

  test "text fields are case and accent insensitive" do
    result = call(expected: expected_json, actual: expected_json.merge("category" => "COMIDA"))
    assert result[:full_match]

    result = call(expected: expected_json, actual: expected_json.merge("money_source" => "  nequi  "))
    assert result[:full_match]
  end

  test "a single wrong field marks the case as failed" do
    result = call(expected: expected_json, actual: expected_json.merge("amount" => 30_000))

    assert_equal true, result[:valid]
    assert_equal false, result[:full_match]
    assert_equal false, result.dig(:fields, :amount, :matched)
    assert result.dig(:fields, :category, :matched)
  end

  test "fields absent from the expected document are not required to match" do
    expected = { "amount" => 20_000, "category" => "Comida" }
    result = call(expected: expected, actual: expected_json)

    assert_equal true, result[:full_match]
    assert_equal 2, result[:fields].count { |_field, value| value[:compared] }
  end

  test "an actual result that is not a hash is invalid and never matches" do
    result = call(expected: expected_json, actual: nil)

    assert_equal false, result[:valid]
    assert_equal false, result[:full_match]
  end

  test "a nil expected field is skipped instead of failing" do
    expected = expected_json.merge("subcategory" => nil)
    result = call(expected: expected, actual: expected_json)

    assert result[:full_match]
  end
end