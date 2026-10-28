# frozen_string_literal: true

# Reports::AvailableCycleController
# GET /reports/available_cycle — available money for the current cycle.
class Reports::AvailableCycleController < Reports::BaseController
  content_security_policy do |policy|
    policy.style_src :self, "https://fonts.googleapis.com", :unsafe_inline
  end

  def index
    @report = Reports::AvailableCycle.new(user: current_user).call
  end
end