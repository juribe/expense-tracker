class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    load_dashboard
  rescue ArgumentError
    flash.now[:alert] = I18n.t("dashboard.invalid_month", default: "El mes no es válido; se muestra el mes actual.")
    params.delete(:month)
    params.delete(:cycle)
    load_dashboard
  end

  private

  def load_dashboard
    resolve_period
    @expense_summary = Expense.dashboard_summary(user: current_user, range: @span)
    @cycle_summary = Dashboard::CycleSummary.new(user: current_user, span: @span, previous_span: previous_span).call
    @budgets = current_user.budgets.includes(:category)
    @goals = current_user.goals.includes([ :pocket, :goal_allocations ]).order(:id)
    @pending_candidates = current_user.expense_candidates.pending.includes(:category).limit(10)
    @categories = Category.for_user_and_type(current_user, "expense")
    @money_sources = MoneySource.payment_origins(current_user)
    @balance_snapshot = balance_snapshot
  end

  # Read-only position snapshot for the financial overview: asset balances
  # (accounts/cash/wallets/debit cards), pockets and outstanding debt, from
  # the existing cached_balance column.
  def balance_snapshot
    sources = current_user.money_sources
    assets = sources.where(kind: %w[account debit_card cash wallet]).filter_map(&:balance).sum
    pockets = sources.pockets.filter_map(&:balance).sum
    debt = sources.debt_payment_targets.filter_map(&:balance).sum
    { assets: assets, pockets: pockets, debt: debt, net: assets + pockets - debt }
  end

  # The equivalent previous window (a month back, or the prior cycle), so the
  # dashboard can show deltas against a like-for-like period.
  def previous_span
    length = (@span.last - @span.first).to_i + 1
    (@span.first - length.days)..(@span.first - 1.day)
  end

  # Calendar month by default; a pay cycle when the user configured paydays,
  # navigable with ?cycle=<any date in the cycle>. The cycle (or nil) is
  # exposed for the header banner so the current financial cycle is visible.
  def resolve_period
    @budget_period = nil
    @cycle = nil
    if Reports::Period.cycles_enabled?(current_user)
      anchor = params[:cycle].present? ? Date.parse(params[:cycle]) : Date.current
      @budget_period = PayCycle.containing(current_user, anchor)
      @cycle = @budget_period
      @span = @budget_period.to_range
      @period_label = @budget_period.label
    else
      @month = params[:month] ? Date.parse(params[:month]) : Time.zone.today
      @budget_period = @month
      @span = @month.beginning_of_month..@month.end_of_month
      @period_label = I18n.l(@month, format: :month_year)
    end
  end
end
