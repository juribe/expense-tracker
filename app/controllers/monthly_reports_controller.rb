class MonthlyReportsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_monthly_report, only: [:show]

  def index
    @monthly_reports = current_user.expenses
      .select("strftime('%Y-%m', date) as month, SUM(amount) as total, COUNT(*) as count")
      .group("strftime('%Y-%m', date)")
      .order("month DESC")
      
    @monthly_summary = @monthly_reports.map do |report|
      {
        month: report.month,
        total: report.total,
        count: report.count
      }
    end
  end

  def show
    @month = params[:id]
    @expenses = current_user.expenses
      .where("strftime('%Y-%m', date) = ?", @month)
      .order(date: :desc)
      
    @total = @expenses.sum(:amount)
    @by_category = @expenses.joins(:category)
      .group('categories.name')
      .sum(:amount)
  end

  private

  def set_monthly_report
    @month = params[:id]
  end
end
