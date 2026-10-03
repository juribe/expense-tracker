# frozen_string_literal: true

# Reports::TransfersController
# GET /reports/transfers — movements between sources.
# Delegates all aggregation to Reports::Transfers; keeps the controller fat-free.
class Reports::TransfersController < Reports::BaseController
  def index
    @transfers = Reports::Transfers.new(user: current_user, filter: report_filters).call
  end
end
