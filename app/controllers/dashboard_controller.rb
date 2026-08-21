class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    @month = params[:month] ? Date.parse(params[:month]) : Time.zone.today
    @expense_summary = Expense.dashboard_summary(user: current_user, month: @month)
    @income_summary = Income.dashboard_summary(user: current_user, month: @month)
    @net_balance = @income_summary[:total_amount] + @expense_summary[:total_amount]
    @summary = @expense_summary
  rescue ArgumentError => e
    flash.now[:alert] = "Invalid month parameter – showing current month."
    @month = Time.zone.today
    @expense_summary = Expense.dashboard_summary(user: current_user, month: @month)
    @income_summary = Income.dashboard_summary(user: current_user, month: @month)
    @net_balance = @income_summary[:total_amount] + @expense_summary[:total_amount]
    @summary = @expense_summary
  end
end
