# frozen_string_literal: true

# Reports::TransactionsController
# GET /reports/transactions — drill-down list of underlying expenses honoring
# the shared filters, paginated with will_paginate.
class Reports::TransactionsController < Reports::BaseController
  def index
    @transactions = report_filters.expense_scope(@period.range)
                                  .includes(:category, :money_source)
                                  .order(date: :desc, created_at: :desc)
                                  .paginate(page: params[:page], per_page: 25)
  end
end
