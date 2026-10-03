# frozen_string_literal: true

# Reports::OverviewController
# GET /reports — dashboard summary cards and quick previews.
# Delegates all aggregation to Reports::Overview; keeps the controller fat-free.
class Reports::OverviewController < Reports::BaseController
  def index
    @overview = Reports::Overview.new(user: current_user, filter: report_filters).call
    @insights = Reports::Insights.new(user: current_user, filter: report_filters).call
    @category_preview = Reports::CategorySpending.new(user: current_user, filter: report_filters).call[:categories].first(4)
  end
end
