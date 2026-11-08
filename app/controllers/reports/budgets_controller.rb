# frozen_string_literal: true

# Reports::BudgetsController
# GET /reports/budgets — budget vs actual per category.
# Delegates all aggregation to Reports::Budgets; keeps the controller fat-free.
class Reports::BudgetsController < Reports::BaseController
  def index
    @budgets = Reports::Budgets.new(user: current_user, filter: report_filters).call
  end

  private

  # Budgets compare category targets with total spending, so narrowing by
  # money source would make the comparison misleading. Only categories apply.
  def report_filter_params
    params.permit(:category_id).to_h.symbolize_keys
  end
end
