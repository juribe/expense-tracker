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

  test "spending trend bucket ranges map days and clamp partial weeks" do
    daily = Reports::Period.new(preset: "this_month", date: Date.new(2026, 9, 15))
    assert_equal Date.new(2026, 9, 3)..Date.new(2026, 9, 3),
                 spending_trend_bucket_range(Date.new(2026, 9, 3), daily)

    weekly = Reports::Period.new(preset: "last_3_months", date: Date.new(2026, 9, 15))
    assert_equal Date.new(2026, 7, 1)..Date.new(2026, 7, 5),
                 spending_trend_bucket_range(Date.new(2026, 6, 29), weekly)
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

  test "budget usage levels follow the 75 and 90 percent thresholds" do
    assert_equal :safe, budget_usage_level(74.9)
    assert_equal :warning, budget_usage_level(75)
    assert_equal :warning, budget_usage_level(89.9)
    assert_equal :critical, budget_usage_level(90)
    assert_equal :critical, budget_usage_level(124)
    assert_equal :none, budget_usage_level(nil)
  end

  test "budget usage width clamps to the progress track" do
    assert_equal 0, budget_usage_width(nil)
    assert_equal 55, budget_usage_width(55.4)
    assert_equal 100, budget_usage_width(140)
  end

  test "budget chart splits actual spending by usage level" do
    rows = [
      { category_name: "Comida", budget: 1_000.to_d, actual: 500.to_d, pct_used: 50.0 },
      { category_name: "Transporte", budget: 1_000.to_d, actual: 800.to_d, pct_used: 80.0 },
      { category_name: "Salud", budget: 1_000.to_d, actual: 1_100.to_d, pct_used: 110.0 }
    ]

    chart = budget_chart_data(rows)

    assert_equal [ "Presupuesto", "Dentro del presupuesto", "Cerca del límite", "Al límite o excedido" ],
                 chart[:series].map { |series| series[:name] }
    assert_equal [ "Comida" ], chart[:series][1][:data].map(&:first)
    assert_equal [ "Transporte" ], chart[:series][2][:data].map(&:first)
    assert_equal [ "Salud" ], chart[:series][3][:data].map(&:first)
    assert_equal 4, chart[:colors].size
  end
end
