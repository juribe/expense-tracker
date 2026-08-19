class ReportsController < ApplicationController
  # GET /reports
  def index
    # Example report – monthly expense totals.
    report = Expense.group_by_month(:created_at, format: "%B %Y").sum(:amount)
    render json: { status: 'ok', report: report }, status: :ok
  rescue StandardError => e
    render json: { status: 'error', message: e.message }, status: :internal_server_error
  end
end