# frozen_string_literal: true

# Reports::CategorySpendingController
# GET /reports/by_category — actual spending grouped by category.
# Delegates all aggregation to Reports::CategorySpending; keeps the controller fat-free.
class Reports::CategorySpendingController < Reports::BaseController
  # Chartkick/Chart.js render charts with inline styles; only the chart
  # reports relax the strict global style-src (see the CSP initializer).
  content_security_policy do |policy|
    policy.style_src :self, "https://fonts.googleapis.com", :unsafe_inline
  end

  def index
    @category_spending = Reports::CategorySpending.new(user: current_user, filter: report_filters).call
  end
end
