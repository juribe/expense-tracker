# frozen_string_literal: true

require "test_helper"

class ReportsAnalysisTest < ActiveSupport::TestCase
  def overview(income:, expenses:, debt: 0, net: nil)
    {
      income: { total: income.to_d, previous: 0.to_d, delta_pct: nil, count: income.positive? ? 1 : 0 },
      expenses: { total: expenses.to_d, previous: 0.to_d, delta_pct: nil,
                  count: expenses.positive? ? 1 : 0 },
      debt: { total: debt.to_d, previous: 0.to_d, delta_pct: nil, count: debt.positive? ? 1 : 0 },
      transfers: { total: 0.to_d, count: 0 },
      net_cash_flow: (net || income - expenses - debt).to_d
    }
  end

  def category(total:, share_pct:, name: "Alimentación")
    { id: "category-1", name: name, total: total.to_d, share_pct: share_pct, count: 1, previous: nil,
      delta_pct: nil }
  end

  def analysis(overview:, categories: [], insights: [], insufficient_data: false)
    Reports::Analysis.new(
      overview: overview,
      categories: categories,
      insights: insights,
      insights_insufficient_data: insufficient_data
    ).call
  end

  test "computes savings capacity and expense share from real totals" do
    data = analysis(overview: overview(income: 10_000_000, expenses: 2_000_000, debt: 1_000_000))

    assert data[:available]
    assert_equal 7_000_000.to_d, data[:net_cash_flow]
    assert_in_delta 70.0, data[:savings_rate], 0.01
    assert_in_delta 20.0, data[:expense_share_pct], 0.01
  end

  test "is unavailable when the period has no movements" do
    data = analysis(overview: overview(income: 0, expenses: 0))

    assert_not data[:available]
    assert_nil data[:savings_rate]
    assert_empty data[:recommendations]
  end

  test "exposes the top category and its concentration recommendation" do
    food = category(total: 4_000_000, share_pct: 40.0)

    data = analysis(
      overview: overview(income: 12_000_000, expenses: 10_000_000),
      categories: [ food ]
    )

    assert_equal food, data[:top_category]
    assert_includes data[:recommendations].map { |row| row[:kind] }, :top_category
  end

  test "turns existing insights into alerts without inventing new ones" do
    insights = [
      { kind: "increase", message: "Tus gastos subieron 25%." },
      { kind: "decrease", message: "Tu gasto en Transporte bajó 12%." },
      { kind: "anomaly", message: "Tienes una transacción grande." },
      { kind: "increase", message: "Cuarta alerta que no cabe." }
    ]

    data = analysis(overview: overview(income: 5_000_000, expenses: 1_000_000), insights: insights)

    assert_equal 2, data[:alerts].size
    assert_equal "Tus gastos subieron 25%.", data[:alerts].first[:message]
    assert_equal "increase", data[:alerts].first[:kind]
  end

  test "flags a negative net flow backed by the overview" do
    data = analysis(overview: overview(income: 1_000_000, expenses: 1_200_000, debt: 300_000))

    assert_operator data[:savings_rate], :<, 0
    assert_includes data[:recommendations].map { |row| row[:kind] }, :negative_flow
  end

  test "does not invent a savings rate when there is no income" do
    data = analysis(overview: overview(income: 0, expenses: 800_000))

    assert data[:available]
    assert_nil data[:savings_rate]
    assert_nil data[:expense_share_pct]
    assert data[:facts].any? { |fact| fact.include?("No registraste ingresos") }
  end
end
