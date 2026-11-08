# frozen_string_literal: true

# Reports::MoneySourcesController
# GET /reports/money_sources — where spending originates.
# Delegates all aggregation to Reports::MoneySources; keeps the controller fat-free.
class Reports::MoneySourcesController < Reports::BaseController
  def index
    @money_sources = Reports::MoneySources.new(user: current_user, filter: report_filters).call
  end

  private

  # Spending is grouped by its source in this report, so a category filter has
  # no place here; ignore it even if it arrives in the URL.
  def report_filter_params
    super.except(:category_id)
  end
end
