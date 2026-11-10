# frozen_string_literal: true

# Reports::Perspectives::Recommendations
# Practical next steps derived from the same metrics and findings. Each
# recommendation is complementary to the findings: when a finding already
# links to a report, the recommendation proposes a different action (a budget,
# a goal, sources, or the full trend) instead of repeating the same message.
#
# Recommendations are never emitted without a previous period to compare
# against, and they never suggest a specific amount to save.
#
# Methods: call
#
# Example: Reports::Perspectives::Recommendations.new(user:, metrics:, comparison:, findings:).call
class Reports::Perspectives::Recommendations
  def initialize(user:, metrics:, comparison:, findings:)
    @user = user
    @metrics = metrics
    @comparison = comparison
    @findings = findings
  end

  attr_reader :user, :metrics, :comparison, :findings

  def call
    return [ review_movements ] unless current_activity?
    return [ review_movements ] unless comparison[:available]

    rows = []
    rows << budget_growth if growth_category
    rows << savings if positive_balance?
    rows << source_concentration if concentrated_source?
    rows << compare_cycles if compare_cycles?
    rows << review_movements if rows.empty?

    rows.compact.uniq { |row| row[:key] }
        .first(Reports::Perspectives::Thresholds::MAX_RECOMMENDATIONS)
  end

  private

  def current_activity?
    metrics[:income][:total].to_d.positive? || metrics[:expenses][:total].to_d.positive?
  end

  def growth_category
    @growth_category ||= comparison[:top_growth].find { |row| row[:id].present? }
  end

  def positive_balance?
    metrics[:income][:total].to_d.positive? && metrics[:balance].to_d.positive?
  end

  def concentrated_source?
    top = metrics[:sources].max_by { |row| row[:total].to_d }
    top && top[:share_pct].to_f >= Reports::Perspectives::Thresholds::SOURCE_CONCENTRATION_PCT
  end

  def compare_cycles?
    return false if findings.any? { |finding| finding.dig(:action, :key) == :trends }

    true
  end

  def budget_growth
    return nil if budgeted_category_ids.include?(growth_category[:id])

    body = if growth_category[:delta_pct].nil?
      I18n.t("reports.perspectives.recommendations.budget_growth.body_no_base",
             amount: currency(growth_category[:delta].abs))
    else
      I18n.t("reports.perspectives.recommendations.budget_growth.body",
             pct: percentage(growth_category[:delta_pct].abs))
    end

    recommendation(
      :budget_growth,
      title: I18n.t("reports.perspectives.recommendations.budget_growth.title", name: growth_category[:name]),
      body: body,
      action: { key: :budgets, label: I18n.t("reports.perspectives.actions.budget"),
                category_id: growth_category[:id] }
    )
  end

  def savings
    recommendation(
      :savings,
      title: I18n.t("reports.perspectives.recommendations.savings.title"),
      body: I18n.t("reports.perspectives.recommendations.savings.body"),
      action: { key: :goals, label: I18n.t("reports.perspectives.actions.goals") }
    )
  end

  def source_concentration
    top = metrics[:sources].max_by { |row| row[:total].to_d }

    recommendation(
      :source_concentration,
      title: I18n.t("reports.perspectives.recommendations.source_concentration.title"),
      body: I18n.t("reports.perspectives.recommendations.source_concentration.body",
                   name: top[:name], pct: percentage(top[:share_pct])),
      action: { key: :money_sources, label: I18n.t("reports.perspectives.actions.money_sources") }
    )
  end

  def compare_cycles
    recommendation(
      :compare_cycles,
      title: I18n.t("reports.perspectives.recommendations.compare_cycles.title"),
      body: I18n.t("reports.perspectives.recommendations.compare_cycles.body"),
      action: { key: :trends, label: I18n.t("reports.perspectives.actions.trends") }
    )
  end

  def review_movements
    recommendation(
      :review_movements,
      title: I18n.t("reports.perspectives.recommendations.review_movements.title"),
      body: I18n.t("reports.perspectives.recommendations.review_movements.body"),
      action: { key: :transactions, label: I18n.t("reports.perspectives.actions.movements") }
    )
  end

  def budgeted_category_ids
    @budgeted_category_ids ||= Budget.for_user(user)
                                     .where(category_id: comparison[:top_growth].map { |row| row[:id] })
                                     .pluck(:category_id)
  end

  def recommendation(key, title:, body:, action:)
    {
      key: key,
      title: title,
      body: body,
      action: action
    }
  end

  def percentage(value)
    ActionController::Base.helpers.number_to_percentage(
      value, precision: 1, strip_insignificant_zeros: true
    )
  end

  def currency(value)
    MoneyFormat.currency(value)
  end
end
