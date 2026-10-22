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

      test "an explicit date wins over the weekday word" do
        today = Date.new(2026, 10, 22)

        result = Service.detect_date("10:38, jueves, 22 de octubre de 2026", today: today)

        assert_equal Date.new(2026, 10, 22), result.first
        assert_operator result.last, :>=, 0.9
      end

      test "parses explicit Spanish dates without a year in the current year" do
        today = Date.new(2026, 10, 22)

        assert_equal Date.new(2026, 10, 5), Service.parse_explicit_date("5 de octubre", today: today)
      end

      test "parses numeric day-first dates" do
        today = Date.new(2026, 10, 22)

        assert_equal Date.new(2026, 10, 22), Service.parse_explicit_date("22/10/2026", today: today)
        assert_equal Date.new(2026, 10, 22), Service.parse_explicit_date("22-10-2026", today: today)
      end

      test "parse_explicit_date is case and accent insensitive" do
        today = Date.new(2026, 10, 22)

        assert_equal Date.new(2026, 10, 22), Service.parse_explicit_date("22 de Octubre de 2026", today: today)
        assert_equal Date.new(2026, 3, 8), Service.parse_explicit_date("8 de Marzo de 2026", today: today)
      end

      test "scan_dates includes explicit calendar dates" do
        today = Date.new(2026, 10, 22)

        assert_equal [ Date.new(2026, 10, 22) ], Service.scan_dates("22 de octubre de 2026", today: today)
      end

      test "parse_explicit_date returns nil for non-date text" do
        assert_nil Service.parse_explicit_date("Cba*Syntevo", today: Date.new(2026, 10, 22))
        assert_nil Service.parse_explicit_date("10:38", today: Date.new(2026, 10, 22))
      end
    end
  end
end
