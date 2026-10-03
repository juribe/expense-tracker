# frozen_string_literal: true

# Reports::SpendingTrendController
# GET /reports/trends — spending over time, bucketed day/week/month.
# Delegates all aggregation to Reports::SpendingTrend; keeps the controller fat-free.
class Reports::SpendingTrendController < Reports::BaseController
  def index
    @spending_trend = Reports::SpendingTrend.new(user: current_user, filter: report_filters).call
  end
end
