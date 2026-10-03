# frozen_string_literal: true

# Reports::RecurringController
# GET /reports/recurring — recurring payments and commitments.
# Delegates all aggregation to Reports::Recurring; keeps the controller fat-free.
class Reports::RecurringController < Reports::BaseController
  def index
    @recurring = Reports::Recurring.new(user: current_user, filter: report_filters).call
  end
end
