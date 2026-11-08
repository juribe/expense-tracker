# frozen_string_literal: true

# MonthlyReportsController
# GET /monthly_reports — "Balance del ciclo": income, expenses and net result
# for each financial cycle covered by the period selected in the shared
# reports period picker. Without a configured financial cycle the cycles are
# plain calendar months.
class MonthlyReportsController < Reports::BaseController
  def index
    @cycles = PayCycle.cycles_between(current_user, @period.range).map { |cycle| cycle_summary(cycle) }
  end

  def show
    @range = range_for(params[:id])
    @incomes = current_user.incomes
      .includes(:category)
      .where(date: @range)
      .order(date: :desc)

    @expenses = current_user.expenses
      .includes(:category)
      .where(date: @range)
      .order(date: :desc)

    @transactions = (@incomes.to_a + @expenses.to_a)
                    .sort_by { |record| [ record.date, record.created_at || Time.at(0) ] }
                    .reverse
    @income_total = @incomes.sum(:amount)
    @expense_total = @expenses.sum(:amount)
    @net_total = @income_total + @expense_total
  end

  private

  # A stale or hand-typed period key must never break the report.
  def range_for(key)
    PayCycle.key_range(current_user, key)
  rescue ArgumentError, Date::Error
    PayCycle.current(current_user).to_range
  end

  def cycle_summary(cycle)
    range = cycle.to_range
    income_total = @report_filters.income_scope(range).sum(:amount).to_d
    expense_total = @report_filters.expense_scope(range).sum(:amount).to_d

    {
      key: PayCycle.period_for(current_user, cycle.starts).first,
      label: cycle.label,
      range_label: cycle.range_label,
      income_total: income_total,
      expense_total: expense_total,
      net_total: income_total + expense_total,
      count: @report_filters.income_scope(range).count + @report_filters.expense_scope(range).count
    }
  end
end
