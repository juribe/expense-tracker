# frozen_string_literal: true

require "test_helper"

class McpNextPaymentDateTest < ActiveSupport::TestCase
  test "returns the configured day in the current month when it is still ahead" do
    assert_equal Date.new(2026, 11, 15), Mcp::NextPaymentDate.for(15, from: Date.new(2026, 11, 10))
  end

  test "keeps the configured day when the reference date is that same day" do
    assert_equal Date.new(2026, 11, 15), Mcp::NextPaymentDate.for(15, from: Date.new(2026, 11, 15))
  end

  test "rolls to the following month once the configured day has passed" do
    assert_equal Date.new(2026, 12, 15), Mcp::NextPaymentDate.for(15, from: Date.new(2026, 11, 16))
  end

  test "rolls over the year from december to january" do
    assert_equal Date.new(2027, 1, 5), Mcp::NextPaymentDate.for(5, from: Date.new(2026, 12, 20))
  end

  test "clamps to the last day of a short month" do
    assert_equal Date.new(2026, 2, 28), Mcp::NextPaymentDate.for(31, from: Date.new(2026, 2, 1))
  end

  test "returns nil when no payment day is configured" do
    assert_nil Mcp::NextPaymentDate.for(nil)
  end
end
