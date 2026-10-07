# frozen_string_literal: true

# "Día de Cuadre" — reconciliation workspace for reaching "Todo cuadrado":
# pending recurring payments assigned to real expenses, and account/card
# balances verified against reality. Reads the persisted state, never
# recomputes per request (Reconciliation::State).
class ReconciliationsController < ApplicationController
  before_action :set_period
  before_action :set_template, only: [ :assign_payment ]
  before_action :set_source, only: [ :set_actual_balance, :leave_pending ]

  def show
    @state = Reconciliation::State.call(current_user, period: @period)
  end

  # Explicit "Refresh" action: force recalculation and persist it.
  def refresh
    Reconciliation::State.refresh!(current_user, period: @period)
    redirect_to reconciliation_path, notice: t("reconciliation.flashes.refreshed")
  end

  # POST — assigns ONE existing expense to a recurring template. Reuses the
  # same service (and guards) as the expenses page assign flow. The cuadre
  # period is enforced: only an expense dated inside the period can clear the
  # pending row, so the assign never leaves the row pending "forever".
  def assign_payment
    result = Expenses::RecurringAssignment.assign(
      user: current_user,
      expense_id: params[:expense_id],
      recurring_template_id: @template.id,
      period: @period
    )

    if result.success?
      Reconciliation::State.refresh!(current_user, period: @period)
      redirect_to reconciliation_path(period: @period),
                  notice: t("reconciliation.flashes.assigned", description: result.description)
    else
      redirect_to reconciliation_path(period: @period),
                  alert: t("reconciliation.flashes.assign_failed", reason: assign_failure_reason(result))
    end
  end

  # GET — JSON search of the user's expenses for the Asignar modal: matches
  # by description and/or expected amount, restricted to the cuadre period
  # month. This is where Gmail-created expenses/candidates-turned-expenses
  # simply appear as selectable results.
  def search_expenses
    expenses = Reconciliation::ExpenseSearch.call(
      user: current_user,
      query: params[:q],
      amount: params[:amount],
      template_id: params[:template_id],
      period: @period
    )

    render json: { expenses: expenses.map { |expense| expense_payload(expense) } }
  end

  # GET — JSON search of movements (expenses + incomes) that could explain a
  # balance difference, for the "Buscar movimiento" action of the Conciliar
  # modal.
  def search_movements
    movements = Reconciliation::MovementSearch.call(
      user: current_user,
      query: params[:q],
      amount: params[:amount]
    )

    render json: { movements: movements.map { |movement| movement_payload(movement) } }
  end

  # POST — records the real balance entered in the Conciliar modal; when
  # `adjust` is set the app balance is corrected (no transaction created).
  # `mark_ok` ("Todo está bien") leaves the balance as is and marks the
  # source reconciled for the period.
  def set_actual_balance
    Reconciliation::CheckBalance.call(
      user: current_user,
      money_source: @source,
      actual_balance: params[:actual_balance],
      adjust: ActiveModel::Type::Boolean.new.cast(params[:adjust]),
      mark_ok: ActiveModel::Type::Boolean.new.cast(params[:mark_ok]),
      note: params[:note]
    )
    Reconciliation::State.refresh!(current_user, period: @period)

    flash_key = params[:mark_ok].present? ? "reconciled_ok" : "balance_checked"
    redirect_to reconciliation_path, notice: t("reconciliation.flashes.#{flash_key}")
  end

  # POST — "Dejar pendiente": the discrepancy stays visible without forcing a
  # resolution. A balance difference is NOT automatically an expense.
  def leave_pending
    Reconciliation::LeavePending.call(user: current_user, money_source: @source, period: @period)
    Reconciliation::State.refresh!(current_user, period: @period)

    redirect_to reconciliation_path, notice: t("reconciliation.flashes.left_pending")
  end

  private

  def set_period
    @period = params[:period].presence || PayCycle.period_for(current_user).first
    unless @period.match?(/\A\d{4}-\d{2}(-\d{2})?\z/)
      @period = PayCycle.period_for(current_user).first
    end
    resolve_cycle
  end

  # The cuadre period as something displayable: the PayCycle::Cycle when the
  # user configured paydays (period key = the cycle start), or the plain
  # calendar month otherwise. Shown in the header so the cuadre period is
  # always visible.
  def resolve_cycle
    if Reports::Period.cycles_enabled?(current_user)
      @cycle = PayCycle.containing(current_user, Date.iso8601(@period))
      @period_label = @cycle.label
    else
      @cycle = nil
      year, month = @period.split("-").map(&:to_i)
      @period_label = I18n.l(Date.new(year, month, 1), format: :month_year)
    end
  end

  def set_template
    @template = current_user.recurring_templates.find(params[:recurring_template_id])
  end

  def set_source
    @source = current_user.money_sources.find(params[:money_source_id])
  end

  def assign_failure_reason(result)
    t("expenses.assign_recurring.#{result.message_key}", description: result.description, default: result.message_key)
  end

  def expense_payload(expense)
    {
      id: expense.id,
      description: expense.description,
      amount: expense.amount.abs.to_s,
      date: expense.date.iso8601
    }
  end

  def movement_payload(movement)
    {
      id: movement.id,
      kind: movement.kind,
      description: movement.description,
      amount: movement.amount.abs.to_s,
      date: movement.date.iso8601,
      edit_url: movement.kind == "income" ? edit_income_path(movement) : edit_expense_path(movement)
    }
  end
end
