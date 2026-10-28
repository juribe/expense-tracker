# frozen_string_literal: true

# Dashboard::CycleSummary
# Aggregates the data the redesigned dashboard cards need for the resolved
# period: totals and deltas vs. the equivalent previous period, a zero-filled
# daily income/expense series, top spending categories, cycle progress with
# the projected spend, and upcoming payments from recurring expense
# templates.
#
# Methods: call
#
# Example: Dashboard::CycleSummary.new(user:, span:, previous_span:).call[:projected_spend]
class Dashboard::CycleSummary
  UPCOMING_DAYS = 10

  # A straight-line projection needs enough elapsed days to be meaningful:
  # extrapolating day 2 or 3 of a month-in-life cycle inflates the number an
  # order of magnitude. Below this, no projection is offered.
  MIN_DAYS_FOR_PROJECTION = 5

  # With this many active recurring expense templates the projection stops
  # extrapolating a daily rate and uses real commitments instead: they work
  # from day 1 because they do not need elapsed-day averaging.
  MIN_RECURRING_TEMPLATES = 3

  def initialize(user:, span:, previous_span:)
    @user = user
    @span = span
    @previous_span = previous_span
  end

  def call
    {
      income_total: income_total,
      expense_total: expense_total,
      expense_count: expense_count,
      net_total: net_total,
      income_delta_pct: income_delta_pct,
      expense_delta_pct: expense_delta_pct,
      net_delta_pct: net_delta_pct,
      evolution: evolution,
      top_categories: top_categories,
      days_elapsed: days_elapsed,
      days_total: days_total,
      period_progress_pct: period_progress_pct,
      projected_spend: projected_spend,
      projection_basis: projection_basis,
      on_track: on_track?,
      upcoming_payments: upcoming_payments
    }
  end

  # Next date whose day matches the template's payment day, clamped to the
  # month end (day 31 in a 28-day month becomes the 28th).
  def self.next_occurrence_date(payment_day, from: Date.current)
    day = [ payment_day, from.end_of_month.day ].min
    candidate = Date.new(from.year, from.month, day)
    return candidate if candidate >= from

    next_month = from.next_month
    day = [ payment_day, next_month.end_of_month.day ].min
    Date.new(next_month.year, next_month.month, day)
  end

  private

  def income_total
    @income_total ||= Income.dashboard_summary(user: @user, range: @span)[:total_amount].to_d
  end

  def expense_total
    @expense_total ||= Expense.dashboard_summary(user: @user, range: @span)[:total_amount].to_d.abs
  end

  def expense_count
    @expense_count ||= Expense.dashboard_summary(user: @user, range: @span)[:count]
  end

  def previous_income_total
    @previous_income_total ||= Income.dashboard_summary(user: @user, range: @previous_span)[:total_amount].to_d
  end

  def previous_expense_total
    @previous_expense_total ||= Expense.dashboard_summary(user: @user, range: @previous_span)[:total_amount].to_d.abs
  end

  def net_total
    income_total - expense_total
  end

  def previous_net_total
    previous_income_total - previous_expense_total
  end

  def income_delta_pct
    delta_pct(income_total, previous_income_total)
  end

  def expense_delta_pct
    delta_pct(expense_total, previous_expense_total)
  end

  def net_delta_pct
    delta_pct(net_total, previous_net_total)
  end

  def delta_pct(current, previous)
    return nil if previous.to_f <= 0

    (current - previous) / previous * 100
  end

  def evolution
    @evolution ||= build_evolution
  end

  def build_evolution
    incomes = sum_by_date(Income.for_user(@user).where(date: @span), "amount")
    expenses = sum_by_date(Expense.for_user(@user).where(date: @span), "ABS(amount)")

    @span.map do |date|
      {
        date: date,
        income: incomes[date].to_d,
        expense: expenses[date].to_d
      }
    end
  end

  # Group sums whose keys arrive as Dates (SQLite) or strings (other adapters).
  def sum_by_date(scope, expression)
    scope.group(:date).sum(Arel.sql(expression))
         .map { |key, value| [ key.to_date, value ] }
         .to_h
  end

  def top_categories
    @top_categories ||= Expense.dashboard_summary(user: @user, range: @span)[:by_category]
                              .sort_by { |_name, total| -total }
                              .first(5)
                              .map do |name, total|
      {
        name: name,
        total: total,
        percentage: expense_total.to_f.positive? ? (total / expense_total * 100).round(1) : 0.0
      }
    end
  end

  def days_total
    (@span.last - @span.first + 1).to_i
  end

  def days_elapsed
    return 0 if Date.current < @span.first

    [ (Date.current - @span.first).to_i + 1, days_total ].min
  end

  def period_progress_pct
    days_total.to_f.positive? ? days_elapsed.to_f / days_total * 100 : 0.0
  end

  def daily_projection
    expense_total * days_total / days_elapsed.to_d
  end

  # Spent-to-date plus what is still committed on the templates, plus the
  # variable (non-template) spend extrapolated at its observed daily rate.
  # Payments already recorded are inside expense_total, so no double counting.
  def recurring_projection
    expense_total + committed_recurring_remaining + variable_daily_rate * (days_total - days_elapsed)
  end

  def variable_daily_rate
    manual_expense_total / days_elapsed.to_d
  end

  def manual_expense_total
    expense_total - recurring_paid_in_span
  end

  # Active expense templates whose only cycle occurrence falls inside the span.
  def eligible_recurring_templates
    @eligible_recurring_templates ||= RecurringTemplate.for_user(@user).expense.active.where.not(payment_day: nil)
                                                       .select { |template| template_occurrence(template) <= @span.end }
  end

  def template_occurrence(template)
    self.class.next_occurrence_date(template.payment_day, from: @span.first)
  end

  # Per-template payments inside the span, in a single grouped query.
  def recurring_payments_by_template
    @recurring_payments_by_template ||=
      Expense.for_user(@user).where(recurring_template_id: eligible_recurring_templates.map(&:id), date: @span)
             .group(:recurring_template_id).sum(:amount)
             .transform_values { |sum| sum.to_d.abs }
  end

  def committed_recurring_remaining
    eligible_recurring_templates.sum do |template|
      paid = recurring_payments_by_template.fetch(template.id, 0)
      maximum = [ template.amount.to_d - paid, 0 ].max
      maximum
    end
  end

  def recurring_paid_in_span
    recurring_payments_by_template.values.sum
  end

  def projected_spend
    return nil if days_elapsed <= 0

    if projection_basis == :recurring
      recurring_projection
    elsif days_elapsed < MIN_DAYS_FOR_PROJECTION
      nil
    else
      daily_projection
    end
  end

  # nil means "too early to project", not "on track".
  def on_track?
    projected = projected_spend
    return nil if projected.nil?

    projected <= income_total
  end

  # :recurring when the user tracks enough fixed expenses to project real
  # commitments, :daily when only a rate extrapolation is available.
  def projection_basis
    eligible_recurring_templates.count >= MIN_RECURRING_TEMPLATES ? :recurring : :daily
  end

  def upcoming_payments
    templates = RecurringTemplate.for_user(@user).expense.active.where.not(payment_day: nil)

    templates.filter_map do |template|
      next_date = self.class.next_occurrence_date(template.payment_day)
      next unless next_date <= Date.current + UPCOMING_DAYS

      paid_amount = recurring_payments_by_template.fetch(template.id, 0)
      # Hide payments that have already been made in this cycle: only pending
      # (still owed) payments are shown as upcoming.
      next if paid_amount >= template.amount.to_d

      {
        template: template,
        label: template.description.presence || template.category.name,
        amount: template.amount,
        next_date: next_date
      }
    end.sort_by { |payment| payment[:next_date] }
  end
end
