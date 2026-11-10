# frozen_string_literal: true

# Reports::Perspectives
# Orchestrates the "Perspectivas financieras" analysis: one metrics pass,
# period-over-period comparison, deterministic findings, complementary
# recommendations, a contextual summary and a compact spending evolution.
#
# All calculations stay inside the reports services; the view only renders the
# returned hashes. Findings are only produced when a previous period exists, so
# a first cycle never receives speculative conclusions.
#
# The returned structure is intentionally data-only: a future AI narrative can
# consume it without calculating amounts, percentages or trends itself.
#
# Methods: call
#
# Example: Reports::Perspectives.new(user: current_user, filter: report_filters).call
class Reports::Perspectives < Reports::Base
  def call
    metrics = Reports::Perspectives::Metrics.new(user: user, filter: filter).call
    comparison = Reports::Perspectives::Comparison.new(metrics: metrics).call
    findings = Reports::Perspectives::Findings.new(user: user, filter: filter, metrics: metrics,
                                                   comparison: comparison).call

    {
      period: period,
      metrics: metrics,
      comparison: comparison,
      findings: findings,
      recommendations: Reports::Perspectives::Recommendations.new(
        user: user, metrics: metrics, comparison: comparison, findings: findings
      ).call,
      summary: Reports::Perspectives::Summary.new(metrics: metrics, comparison: comparison).call,
      evolution: Reports::Perspectives::Evolution.new(user: user, filter: filter).call,
      available: current_activity?(metrics),
      insufficient_data: current_activity?(metrics) && !comparison[:available],
      partial: metrics[:partial]
    }
  end

  private

  def current_activity?(metrics)
    metrics[:income][:total].to_d.positive? || metrics[:expenses][:total].to_d.positive?
  end
end
