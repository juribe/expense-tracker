class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    load_dashboard
  rescue ArgumentError
    flash.now[:alert] = I18n.t("dashboard.invalid_month", default: "El mes no es válido; se muestra el mes actual.")
    @month = Time.zone.today
    load_dashboard
  end

  private

  def load_dashboard
    @month ||= params[:month] ? Date.parse(params[:month]) : Time.zone.today
    @expense_summary = Expense.dashboard_summary(user: current_user, month: @month)
    @income_summary = Income.dashboard_summary(user: current_user, month: @month)
    @net_balance = @income_summary[:total_amount] + @expense_summary[:total_amount]
    @summary = @expense_summary
    @budgets = current_user.budgets.includes(:category)
    @pending_candidates = current_user.expense_candidates.pending.includes(:category).limit(10)
    @categories = Category.for_user_and_type(current_user, "expense")
    @money_sources = MoneySource.payment_origins(current_user)
  end
end
