# frozen_string_literal: true

# Reports::SpendingTrendController
# GET /reports/trends — spending over time, bucketed day/week/month.
# Delegates all aggregation to Reports::SpendingTrend; keeps the controller fat-free.
class Reports::SpendingTrendController < Reports::BaseController
  # Chartkick/Chart.js render charts with inline styles; only the chart
  # reports relax the strict global style-src (see the CSP initializer).
  content_security_policy do |policy|
    policy.style_src :self, "https://fonts.googleapis.com", :unsafe_inline
  end

  rescue_from ActiveRecord::StatementInvalid, with: :render_report_error

  def index
    @spending_trend = Reports::SpendingTrend.new(
      user: current_user, filter: report_filters, granularity: params[:granularity]
    ).call
    @spending_trend_insights = Reports::SpendingTrendInsights.new(trend: @spending_trend).call
  end

  private

  def render_report_error(exception)
    Rails.logger.error("Spending trend report failed (#{exception.class})")
    @spending_trend_error = true
    render :index, status: :service_unavailable
  end
end
