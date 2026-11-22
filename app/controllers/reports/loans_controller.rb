# frozen_string_literal: true

# Reports::LoansController
# GET /reports/loans — debt overview and consolidated totals.
# Delegates all aggregation to Reports::Loans; keeps the controller fat-free.
class Reports::LoansController < Reports::BaseController
  before_action :require_detailed_money_tracking
  def index
    @loans = Reports::Loans.new(user: current_user, filter: report_filters).call
  end
end
