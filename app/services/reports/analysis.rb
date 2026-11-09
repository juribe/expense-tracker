# frozen_string_literal: true

# Reports::Analysis
# Deterministic narrative for the overview: savings capacity, expense share,
# the top category, the existing insights as alerts, and recommendations that
# are only emitted when the underlying totals support them.
#
# Methods: call
#
# Example: Reports::Analysis.new(overview:, categories:, insights:, insights_insufficient_data:).call
class Reports::Analysis
  MAX_ALERTS = 2
  MAX_FACTS = 2
  MAX_RECOMMENDATIONS = 2
  HIGH_CATEGORY_SHARE_PCT = 30.0
  LOW_SAVINGS_RATE_PCT = 10.0
  HEALTHY_SAVINGS_RATE_PCT = 20.0
  SIGNIFICANT_DEBT_SHARE_PCT = 20.0

  def initialize(overview:, categories:, insights:, insights_insufficient_data:)
    @overview = overview
    @categories = categories
    @insights = insights
    @insights_insufficient_data = insights_insufficient_data
  end

  def call
    {
      available: available?,
      savings_rate: savings_rate,
      net_cash_flow: net_cash_flow,
      expense_share_pct: expense_share_pct,
      top_category: top_category,
      facts: facts,
      alerts: alerts,
      recommendations: recommendations.compact.first(MAX_RECOMMENDATIONS),
      insights_insufficient_data: insights_insufficient_data
    }
  end

  private

  attr_reader :overview, :categories, :insights, :insights_insufficient_data

  def available?
    income_total.positive? || expense_total.positive? || debt_total.positive?
  end

  def income_total
    overview[:income][:total].to_d
  end

  def expense_total
    overview[:expenses][:total].to_d
  end

  def debt_total
    overview[:debt][:total].to_d
  end

  def net_cash_flow
    overview[:net_cash_flow].to_d
  end

  def savings_rate
    return nil unless income_total.positive?

    (net_cash_flow / income_total * 100).round(1).to_f
  end

  def expense_share_pct
    return nil unless income_total.positive?

    (expense_total / income_total * 100).round(1).to_f
  end

  def debt_share_pct
    return nil unless income_total.positive?

    (debt_total / income_total * 100).round(1).to_f
  end

  def top_category
    categories.max_by { |category| category[:total].to_d }
  end

  def facts
    rows = []
    rows << expense_share_fact if income_total.positive? && expense_total.positive?
    rows << no_income_fact if income_total.zero? && expense_total.positive?
    rows << income_delta_fact if income_delta_pct
    rows << debt_total_fact if debt_total.positive?
    rows.first(MAX_FACTS)
  end

  def expense_share_fact
    I18n.t("reports.analysis.facts.expense_share", pct: percentage(expense_share_pct))
  end

  def no_income_fact
    I18n.t("reports.analysis.facts.no_income", amount: MoneyFormat.currency(expense_total))
  end

  def income_delta_fact
    key = income_delta_pct.negative? ? "income_down" : "income_up"
    I18n.t("reports.analysis.facts.#{key}", pct: percentage(income_delta_pct.abs))
  end

  def debt_total_fact
    I18n.t("reports.analysis.facts.debt_total", amount: MoneyFormat.currency(debt_total))
  end

  def income_delta_pct
    value = overview[:income][:delta_pct]
    value.to_f if value.present?
  end

  def alerts
    insights.first(MAX_ALERTS).map do |insight|
      { kind: insight[:kind], message: insight[:message] }
    end
  end

  def recommendations
    rows = []
    rows << recommendation(:negative_flow, amount: MoneyFormat.currency(net_cash_flow.abs)) if negative_flow?
    rows << top_category_recommendation if concentrated_category?
    rows << savings_recommendation if savings_rate
    rows << debt_recommendation if significant_debt?
    rows
  end

  def negative_flow?
    net_cash_flow.negative?
  end

  def concentrated_category?
    top_category.present? && top_category[:share_pct].to_f >= HIGH_CATEGORY_SHARE_PCT
  end

  def significant_debt?
    debt_share_pct.present? && debt_share_pct >= SIGNIFICANT_DEBT_SHARE_PCT
  end

  def top_category_recommendation
    recommendation(:top_category, name: top_category[:name], pct: percentage(top_category[:share_pct]))
  end

  def savings_recommendation
    key = savings_rate < LOW_SAVINGS_RATE_PCT ? :low_savings : :healthy_savings
    return nil unless savings_rate < LOW_SAVINGS_RATE_PCT || savings_rate >= HEALTHY_SAVINGS_RATE_PCT

    recommendation(key, pct: percentage(savings_rate))
  end

  def debt_recommendation
    recommendation(:debt_share, pct: percentage(debt_share_pct))
  end

  def recommendation(key, **options)
    {
      kind: key,
      title: I18n.t("reports.analysis.recommendations.#{key}.title", **options),
      body: I18n.t("reports.analysis.recommendations.#{key}.body", **options)
    }
  end

  def percentage(value)
    ActionController::Base.helpers.number_to_percentage(value, precision: 1)
  end
end
