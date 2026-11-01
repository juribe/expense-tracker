# frozen_string_literal: true

require "test_helper"

class GmfPeriodTest < ActiveSupport::TestCase
  test "returns calendar month for a date" do
    result = Gmf::Period.for(Date.new(2026, 11, 15))
    assert_equal 2026, result[:year]
    assert_equal 11, result[:month]
  end

  test "range covers full calendar month" do
    range = Gmf::Period.range(2026, 11)
    assert_equal Date.new(2026, 11, 1), range.begin
    assert_equal Date.new(2026, 11, 30), range.end
  end

  test "independent of pay cycle start day" do
    # Calendar month always starts on day 1 regardless of financial cycle.
    result = Gmf::Period.for(Date.new(2026, 11, 1))
    assert_equal 11, result[:month]
  end
end
