# frozen_string_literal: true

# Reports::CategorySpendingController
# GET /reports/by_category — actual spending grouped by category.
# Delegates all aggregation to Reports::CategorySpending; keeps the controller fat-free.
class Reports::CategorySpendingController < Reports::BaseController
  def index
    @category_spending = Reports::CategorySpending.new(user: current_user, filter: report_filters).call
  end
end
