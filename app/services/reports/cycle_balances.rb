# frozen_string_literal: true

# Reports::CycleBalances
# Single source of truth for the financial balance of one or more pay cycles:
# valid income, real consumption expenses (never debt repayments) and the
# resulting net flow. Used by both the cycle list and the cycle detail so the
# indicators can never disagree.
#
# A single grouped pass over each side (income and real expenses) computes every
# requested cycle without per-cycle queries or N+1 access.
#
# Methods: call
#
# Example: Reports::CycleBalances.new(user: user, cycles: [cycle]).call.first
class Reports::CycleBalances
  def initialize(user:, cycles:, filter: nil)
    @user = user
    @cycles = Array(cycles).compact
    @filter = filter
  end

  def call
    return [] if cycles.empty?

    cycles.map { |cycle| summary(cycle) }
  end

  private

  attr_reader :user, :cycles, :filter

  def summary(cycle)
    range = cycle.to_range
    income_total = total_for(income_by_date, range)
    expense_total = total_for(expense_by_date, range)
    income_count = count_for(income_count_by_date, range)
    expense_count = count_for(expense_count_by_date, range)
    net_total = income_total - expense_total
    status = status_for(cycle)

    {
      cycle: cycle,
      key: PayCycle.period_for(user, cycle.starts).first,
      label: cycle.label,
      range_label: cycle.range_label,
      short_label: I18n.l(cycle.starts, format: "%b %y"),
      starts: cycle.starts,
      ends: cycle.ends,
      income_total: income_total,
      expense_total: expense_total,
      net_total: net_total,
      savings_rate: savings_rate(net_total, income_total),
      movement_count: income_count + expense_count,
      income_count: income_count,
      expense_count: expense_count,
      status: status,
      current: status == :in_progress,
      partial: status == :in_progress
    }
  end

  def span
    @span ||= cycles.map(&:starts).min..cycles.map(&:ends).max
  end

  def income_by_date
    @income_by_date ||= grouped_sum(income_scope, :amount)
  end

  def expense_by_date
    @expense_by_date ||= grouped_sum(
      actual_expense_scope,
      Arel.sql("ABS(transactions.amount)")
    )
  end

  def income_count_by_date
    @income_count_by_date ||= grouped_count(income_scope)
  end

  def expense_count_by_date
    @expense_count_by_date ||= grouped_count(actual_expense_scope)
  end

  # The optional filter is the shared Reports::Filter used by every report,
  # so the debt-payment rule (an Expense with a Payment is repayment, not
  # consumption) is never reimplemented here.
  def income_scope
    filter ? filter.income_scope(span) : Income.for_user(user).where(date: span)
  end

  def actual_expense_scope
    filter ? filter.actual_expense_scope(span) : Expense.for_user(user).where(date: span).where.missing(:payments)
  end

  def grouped_sum(scope, expression)
    scope.group(:date).sum(expression).each_with_object({}) do |(date, value), result|
      result[date.to_date] = value.to_d
    end
  end

  def grouped_count(scope)
    scope.group(:date).count.each_with_object({}) do |(date, value), result|
      result[date.to_date] = value.to_i
    end
  end

  def total_for(values_by_date, range)
    values_by_date.sum { |date, value| range.cover?(date) ? value : 0 }.to_d
  end

  def count_for(values_by_date, range)
    values_by_date.sum { |date, value| range.cover?(date) ? value : 0 }
  end

  def savings_rate(net_total, income_total)
    return nil if income_total.zero?

    (net_total / income_total * 100).round(1)
  end

  def status_for(cycle)
    today = Date.current
    return :in_progress if today.between?(cycle.starts, cycle.ends)
    return :completed if today > cycle.ends

    :upcoming
  end
end
