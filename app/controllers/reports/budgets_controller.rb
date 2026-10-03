# frozen_string_literal: true

# Reports::BudgetsController
# GET /reports/budgets — budget vs actual per category.
# Delegates all aggregation to Reports::Budgets; keeps the controller fat-free.
class Reports::BudgetsController < Reports::BaseController
  def index
    @budgets = Reports::Budgets.new(user: current_user, filter: report_filters).call
  end
end
