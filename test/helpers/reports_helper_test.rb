# frozen_string_literal: true

require "test_helper"

class ReportsHelperTest < ActionView::TestCase
  setup do
    @user = User.create!(name: "Helper User", email: "reports_helper_test@example.com", password: "password123")
  end

  test "period presets are the calendar months without a configured schedule" do
    assert_equal %w[this_month last_month last_3_months last_6_months last_12_months this_year custom],
                 period_presets(user: @user).map(&:last)
  end

  test "period presets swap months for cycles with a configured schedule" do
    @user.update!(financial_cycle_start_day: 20)
    presets = period_presets(user: @user)

    assert_equal %w[this_cycle last_cycle last_3_cycles last_6_cycles last_12_cycles this_year custom],
                 presets.map(&:last)
    assert_equal [ "Últimos 3 ciclos", "Últimos 6 ciclos", "Últimos 12 ciclos", "Este año", "Rango personalizado" ],
                 presets[2..].map(&:first)
  end

  test "cycle preset labels include the cycle month for clarity" do
    @user.update!(financial_cycle_start_day: 20)
    labels = period_presets(user: @user).to_h.invert

    this_label = labels["this_cycle"]
    last_label = labels["last_cycle"]

    assert_equal "Este ciclo (#{PayCycle.current(@user).label})", this_label
    assert_equal "Ciclo pasado (#{PayCycle.previous(@user).label})", last_label
    assert_match(/20\d\d/, this_label)
  end

  test "available cycle due labels reflect the due date state" do
    travel_to Date.new(2026, 10, 28) do
      assert_equal "Vencido", available_cycle_due_label(due_date: Date.new(2026, 10, 20), overdue: true)
      assert_equal "Hoy", available_cycle_due_label(due_date: Date.current, due_today: true)
      assert_equal "En 3 días", available_cycle_due_label(due_date: Date.new(2026, 10, 31), days_until_due: 3)
      assert_equal "Sin fecha", available_cycle_due_label(due_date: nil)
    end
  end

  test "available cycle share and percentage keep deficits visible" do
    assert_equal 35, available_cycle_share(3_500_000, 10_000_000)
    assert_equal 100, available_cycle_share(12_000_000, 10_000_000)
    assert_equal "-20%", available_cycle_percentage(-2_000_000, 10_000_000)
    assert_equal "—", available_cycle_percentage(1, 0)
  end
end
