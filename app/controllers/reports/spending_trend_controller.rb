# frozen_string_literal: true

# Reports::SpendingTrendController
# GET /reports/trends — spending over time, bucketed day/week/month.
# Delegates all aggregation to Reports::SpendingTrend; keeps the controller fat-free.
class Reports::SpendingTrendController < Reports::BaseController
  # Chartkick/Chart.js render charts with inline styles; only the chart
  # reports relax the strict global style-src (see the CSP initializer).
  content_security_policy do |policy|
    policy.style_src :self, "https://fonts.googleapis.com", :unsafe_inline
  end

  def index
    @spending_trend = Reports::SpendingTrend.new(user: current_user, filter: report_filters).call
  end
end
