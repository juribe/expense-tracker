require "test_helper"

module ExpenseResolver
  module Dates
    class ServiceTest < ActiveSupport::TestCase
      test "detect_date resolves la semana pasada to a week ago" do
        today = Date.new(2026, 9, 26)

        result = Service.detect_date("La semana pasada gasté 25000 en taxi", today: today)

        assert_equal Date.new(2026, 9, 19), result.first
      end

      test "detect_date resolves el mes pasado to the same day last month" do
        today = Date.new(2026, 9, 26)

        result = Service.detect_date("El mes pasado pagué 15000 de parqueadero", today: today)

        assert_equal Date.new(2026, 8, 26), result.first
      end

      test "scan_dates includes relative range expressions" do
        today = Date.new(2026, 9, 26)

        assert_equal [ Date.new(2026, 9, 19) ], Service.scan_dates("la semana pasada", today: today)
        assert_equal [ Date.new(2026, 8, 26) ], Service.scan_dates("el mes pasado", today: today)
        assert_empty Service.scan_dates("gasté 25000 en taxi", today: today)
      end

      test "weekday beats range expressions when both appear" do
        today = Date.new(2026, 9, 26)

        result = Service.detect_date("el lunes de la semana pasada gasté 25000", today: today)

        assert_equal Date.new(2026, 9, 21), result.first
      end
    end
  end
end
