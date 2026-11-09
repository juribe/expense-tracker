# frozen_string_literal: true

# Reports::OverviewController
# GET /reports — dashboard summary cards, behavior chart, category preview,
# financial analysis and secondary indicators.
# Delegates all aggregation to the Reports services; keeps the controller fat-free.
class Reports::OverviewController < Reports::BaseController
  # Chartkick/Chart.js render charts with inline styles; only the chart
  # reports relax the strict global style-src (see the CSP initializer).
  content_security_policy do |policy|
    policy.style_src :self, "https://fonts.googleapis.com", :unsafe_inline
  end

  def index
    @overview = Reports::Overview.new(user: current_user, filter: report_filters).call
    @cash_flow_trend = Reports::CashFlowTrend.new(user: current_user, filter: report_filters).call

    category_spending = Reports::CategorySpending.new(user: current_user, filter: report_filters).call
    @category_preview = category_spending[:categories].first(5)
    @category_preview_total = @category_preview.sum { |category| category[:total] }

    insights = Reports::Insights.new(user: current_user, filter: report_filters)
    @insights = insights.call
    @insights_insufficient_data = insights.insufficient_data?
    @analysis = Reports::Analysis.new(
      overview: @overview,
      categories: category_spending[:categories],
      insights: @insights,
      insights_insufficient_data: @insights_insufficient_data
    ).call
  end
end
