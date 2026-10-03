# frozen_string_literal: true

# Reports::InsightsController
# GET /reports/insights — deterministic spending insights.
# Delegates all aggregation to Reports::Insights; keeps the controller fat-free.
class Reports::InsightsController < Reports::BaseController
  def index
    @insights = Reports::Insights.new(user: current_user, filter: report_filters).call
  end
end
