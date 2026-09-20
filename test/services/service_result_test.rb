# frozen_string_literal: true

require "test_helper"

class ServiceResultTest < ActiveSupport::TestCase
  test "is successful when there are no errors" do
    result = ServiceResult.new(result: "expense")

    assert result.success?
    refute result.failure?
    assert_equal "expense", result.result
    assert_equal [], result.errors
  end

  test "is a failure when there are errors" do
    result = ServiceResult.new(errors: [ "Unable to create expense" ])

    refute result.success?
    assert result.failure?
    assert_nil result.result
    assert_equal [ "Unable to create expense" ], result.errors
  end

  test "returns the result object" do
    expense = Expense.new

    assert_same expense, ServiceResult.new(result: expense).result
  end

  test "defaults result to nil" do
    assert_nil ServiceResult.new.result
  end

  test "accepts any object as result, including nil" do
    assert_nil ServiceResult.new(result: nil).result
    assert_equal "str", ServiceResult.new(result: "str").result
    assert_equal 42, ServiceResult.new(result: 42).result
  end

  test "preserves multiple errors" do
    result = ServiceResult.new(errors: [ "first", "second" ])

    refute result.success?
    assert_equal [ "first", "second" ], result.errors
  end

  test "errors are always an array" do
    assert_equal [ "Unable to create expense" ], ServiceResult.new(errors: "Unable to create expense").errors
    assert_equal [], ServiceResult.new(errors: nil).errors
    assert_equal [], ServiceResult.new.errors
  end

  test "ServiceResult.success builds a successful result" do
    expense = Expense.new
    result = ServiceResult.success(expense)

    assert_same expense, result.result
    assert result.success?
    assert_equal [], result.errors
  end

  test "ServiceResult.error builds a failed result from a string" do
    result = ServiceResult.error("Unable to create expense")

    assert result.failure?
    assert_equal [ "Unable to create expense" ], result.errors
    assert_nil result.result
  end

  test "ServiceResult.error builds a failed result from an array" do
    result = ServiceResult.error([ "first", "second" ])

    assert result.failure?
    assert_equal [ "first", "second" ], result.errors
  end
end
