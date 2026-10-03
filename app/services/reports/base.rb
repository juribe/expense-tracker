# frozen_string_literal: true

# Reports::Base
# Shared plumbing for report services: user/period/filter state plus the
# accounting split that keeps every report consistent — an Expense carrying a
# Payment is a debt payment, never consumption spending, so the same financial
# event is never counted twice.
#
# Methods: actual_expenses, debt_expenses, debt_payment_rows, delta_pct (class)
#
# Example: Reports::Overview.new(user: user, filter: filter).call
class Reports::Base
  attr_reader :user, :filter, :period

  def initialize(user:, filter:)
    @user = user
    @filter = filter
    @period = filter.period
  end

  # Expenses that are consumption spending: no Payment applies them to a debt.
  def actual_expenses(range = period.range)
    filter.expense_scope(range).where.missing(:payments)
  end

  # Expenses that a Payment applies to a credit card or loan.
  def debt_expenses(range = period.range)
    filter.expense_scope(range).joins(:payments).distinct
  end

  # Payment records (with principal/interest/insurance/other components)
  # falling inside the range, per the Payment's date convention.
  def debt_payment_rows(range = period.range)
    Payment.for_user(user).where(date: range)
  end

  def self.delta_pct(current, previous)
    previous = previous.to_d
    return nil if previous.zero?

    ((current.to_d - previous) / previous * 100).round(1)
  end
end
