# frozen_string_literal: true

# Reports::AvailableCycleController
# GET /reports/available_cycle — available money for the current cycle.
class Reports::AvailableCycleController < Reports::BaseController
  def index
    @report = Reports::AvailableCycle.new(user: current_user).call
  end
end