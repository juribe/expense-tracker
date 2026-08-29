class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    @month = params[:month] ? Date.parse(params[:month]) : Time.zone.today
    @expense_summary = Expense.dashboard_summary(user: current_user, month: @month)
    @income_summary = Income.dashboard_summary(user: current_user, month: @month)
    @net_balance = @income_summary[:total_amount] + @expense_summary[:total_amount]
    @summary = @expense_summary
  rescue ArgumentError
    flash.now[:alert] = I18n.t("dashboard.invalid_month", default: "El mes no es válido; se muestra el mes actual.")
    @month = Time.zone.today
    @expense_summary = Expense.dashboard_summary(user: current_user, month: @month)
    @income_summary = Income.dashboard_summary(user: current_user, month: @month)
    @net_balance = @income_summary[:total_amount] + @expense_summary[:total_amount]
    @summary = @expense_summary
  end
end
