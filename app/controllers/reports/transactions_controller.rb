# frozen_string_literal: true

# Reports::TransactionsController
# GET /reports/transactions — drill-down list of underlying expenses honoring
# the shared filters, paginated with will_paginate.
class Reports::TransactionsController < Reports::BaseController
  def index
    scope = report_filters.actual_expense_scope(@period.range)
    ordered = scope.includes(:category, :money_source).order(date: :desc, created_at: :desc)

    if params[:modal].present?
      render partial: "reports/transactions/modal",
             locals: { transactions: ordered.to_a, total: scope.sum(:amount).abs },
             layout: false
      return
    end

    @transactions = ordered.paginate(page: params[:page], per_page: 25)
  end
end
