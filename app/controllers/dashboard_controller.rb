class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    @month = params[:month] ? Date.parse(params[:month]) : Time.zone.today
    @summary = Expense.dashboard_summary(user: current_user, month: @month)
  rescue ArgumentError => e
    flash.now[:alert] = "Invalid month parameter – showing current month."
    @month = Time.zone.today
    @summary = Expense.dashboard_summary(user: current_user, month: @month)
  end
end