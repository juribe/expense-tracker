# frozen_string_literal: true

# MonthlyReportsController
# GET /monthly_reports — "Balance del ciclo": income, real expenses and net
# result for each financial cycle covered by the shared reports period picker.
# GET /monthly_reports/:id — movements that compose one cycle, with filters,
# pagination and CSV export. Both screens share Reports::CycleBalances so their
# indicators always agree.
class MonthlyReportsController < Reports::BaseController
  CYCLES_PER_PAGE = 8
  TRANSACTIONS_PER_PAGE = ApplicationController::PER_PAGE

  def index
    cycles = PayCycle.cycles_between(current_user, @period.range)
    @cycle_balances = Reports::CycleBalances.new(user: current_user, cycles: cycles, filter: balance_filter).call
    @focus_balance = focus_balance
    @comparison = cycle_comparison
    @chart_balances = chart_balances
    @paged_cycles = paginate_cycles(@cycle_balances.reverse)
  end

  def show
    @cycle = cycle_for(params[:id])
    @cycle_balance = Reports::CycleBalances.new(user: current_user, cycles: [ @cycle ], filter: balance_filter).call.first
    @category_options = category_options
    @type_filter = normalized_type
    @filters_active = filters_active?

    respond_to do |format|
      format.html do
        @transactions = transactions_query.call.paginate(page: params[:page], per_page: TRANSACTIONS_PER_PAGE)
      end
      format.csv do
        send_data Reports::CycleTransactionsCsv.new(records: transactions_query.call.to_a).call,
                  filename: "balance-ciclo-#{@cycle.starts.iso8601}.csv",
                  type: "text/csv"
      end
    end
  end

  private

  def focus_balance
    return nil if @cycle_balances.empty?

    focus_date = [ Date.current, @period.range.end ].min
    focus_date = @period.range.begin if focus_date < @period.range.begin

    @cycle_balances.find { |balance| balance[:cycle].to_range.cover?(focus_date) } || @cycle_balances.last
  end

  def cycle_comparison
    return nil unless @focus_balance

    Reports::CycleComparison.new(
      user: current_user,
      cycle: @focus_balance[:cycle],
      current_balance: @focus_balance,
      filter: balance_filter
    ).call
  end

  # The list preset can cover several cycles. Plot them chronologically; when
  # it covers a single cycle, extend the chart with the previous cycles so the
  # selected result has real context.
  def chart_balances
    return [] unless @focus_balance

    selected = @cycle_balances.select { |balance| balance[:starts] <= @focus_balance[:starts] }.last(12)
    return selected if selected.size > 1

    cycles = PayCycle.back(current_user, 6, anchor: @focus_balance[:ends])
    Reports::CycleBalances.new(user: current_user, cycles: cycles, filter: balance_filter).call
  end

  # Cycle indicators ignore the detail-only filters (type, category, search):
  # they must always show the same cycle totals as the list screen.
  def balance_filter
    @balance_filter ||= Reports::Filter.new(user: current_user, period: @period)
  end

  def paginate_cycles(cycles)
    page = [ params[:page].to_i, 1 ].max
    WillPaginate::Collection.create(page, CYCLES_PER_PAGE, cycles.size) do |pager|
      pager.replace(cycles[pager.offset, pager.per_page] || [])
    end
  end

  # A stale or hand-typed period key must never break the report.
  def cycle_for(key)
    range = PayCycle.key_range(current_user, key)
    PayCycle::Cycle.new(starts: range.begin, ends: range.end)
  rescue ArgumentError, Date::Error
    PayCycle.current(current_user)
  end

  def transactions_query
    @transactions_query ||= Reports::CycleTransactionsQuery.new(
      user: current_user,
      range: @cycle.to_range,
      type: params[:type],
      category_id: params[:category_id],
      query: params[:q]
    )
  end

  def normalized_type
    Reports::CycleTransactionsQuery::TYPES.include?(params[:type].to_s) ? params[:type].to_s : "all"
  end

  def filters_active?
    @type_filter != "all" || params[:category_id].present? || params[:q].present?
  end

  def category_options
    categories = Category.for_user(current_user)
                         .where(category_type: %w[expense income])
                         .pluck(:name, :id, :category_type)

    {
      t("types.expense_plural") => categories.select { |_name, _id, type| type == "expense" }
                                              .map { |name, id, _type| [ name, id ] },
      t("types.income_plural") => categories.select { |_name, _id, type| type == "income" }
                                             .map { |name, id, _type| [ name, id ] }
    }
  end
end
