# frozen_string_literal: true

# Reports::MoneySourcesController
# GET /reports/money_sources — where spending originates.
# Delegates all aggregation to Reports::MoneySources; keeps the controller fat-free.
class Reports::MoneySourcesController < Reports::BaseController
  # Chartkick injects inline chart markup and styles; every other style is
  # served from the reports stylesheet.
  content_security_policy do |policy|
    policy.style_src :self, "https://fonts.googleapis.com", :unsafe_inline
  end

  rescue_from ActiveRecord::StatementInvalid, with: :render_report_error

  def index
    @money_sources = Reports::MoneySources.new(
      user: current_user, filter: report_filters, source_kind: params[:source_kind]
    ).call
  end

  private

  def render_report_error(exception)
    Rails.logger.error("Money sources report failed (#{exception.class})")
    @money_sources_error = true
    render :index, status: :service_unavailable
  end

  # Spending is grouped by its source in this report, so a category filter has
  # no place here; ignore it even if it arrives in the URL.
  def report_filter_params
    super.except(:category_id)
  end
end
