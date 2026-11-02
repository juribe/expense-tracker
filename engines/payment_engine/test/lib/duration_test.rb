require "test_helper"

class DurationTest < PaymentEngineTestCase
  test "months use calendar arithmetic and clamp end of month" do
    duration = PaymentEngine::Duration.new(interval: "month", count: 1)

    assert_equal Time.utc(2026, 2, 28, 10), duration.apply_to(Time.utc(2026, 1, 31, 10))
    assert_equal Time.utc(2028, 2, 29, 10), duration.apply_to(Time.utc(2028, 1, 31, 10))
  end

  test "years respect leap years" do
    duration = PaymentEngine::Duration.new(interval: "year", count: 4)

    assert_equal Time.utc(2028, 2, 29, 10), duration.apply_to(Time.utc(2024, 2, 29, 10))
    assert_equal Time.utc(2025, 2, 28, 10),
                 PaymentEngine::Duration.new(interval: "year", count: 1).apply_to(Time.utc(2024, 2, 29, 10))
  end

  test "days and multiple intervals" do
    assert_equal Time.utc(2026, 1, 8), PaymentEngine::Duration.new(interval: "day", count: 7).apply_to(Time.utc(2026, 1, 1))
    assert_equal Time.utc(2026, 4, 1), PaymentEngine::Duration.new(interval: "month", count: 3).apply_to(Time.utc(2026, 1, 1))
  end

  test "serializes and deserializes" do
    duration = PaymentEngine::Duration.new(interval: "month", count: 3)

    assert_equal({ "interval" => "month", "count" => 3 }, duration.to_h)
    assert_equal duration, PaymentEngine::Duration.from(duration.to_h)
    assert_equal duration, PaymentEngine::Duration.from(interval: :month, count: 3)
    assert_equal "3 months", duration.to_s
  end

  test "rejects invalid intervals and counts" do
    assert_raises(ArgumentError) { PaymentEngine::Duration.new(interval: "week") }
    assert_raises(ArgumentError) { PaymentEngine::Duration.new(interval: "month", count: 0) }
  end
end
