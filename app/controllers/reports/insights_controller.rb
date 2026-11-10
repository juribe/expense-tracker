# frozen_string_literal: true

# Reports::InsightsController
# GET /reports/insights — "Perspectivas financieras": summary, deterministic
# findings, recommendations and a compact spending evolution.
# Delegates all aggregation to Reports::Perspectives; keeps the controller
# fat-free.
class Reports::InsightsController < Reports::BaseController
  # Chartkick/Chart.js render the evolution chart with inline styles; only the
  # chart reports relax the strict global style-src (see the CSP initializer).
  content_security_policy do |policy|
    policy.style_src :self, "https://fonts.googleapis.com", :unsafe_inline
  end

  def index
    @perspectives = Reports::Perspectives.new(user: current_user, filter: report_filters).call
  end
end
