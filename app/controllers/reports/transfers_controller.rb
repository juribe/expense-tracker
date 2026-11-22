# frozen_string_literal: true

# Reports::TransfersController
# GET /reports/transfers — movements between sources.
# Delegates all aggregation to Reports::Transfers; keeps the controller fat-free.
class Reports::TransfersController < Reports::BaseController
  before_action :require_detailed_money_tracking
  def index
    @transfers = Reports::Transfers.new(user: current_user, filter: report_filters).call
  end
end
