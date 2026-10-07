# frozen_string_literal: true

# FinancialSummaryService
# Assembles the financial summary snapshot shown on the summary page (and
# reusable as context for the chat's insight cards): income/expenses for the
# period and the previous one, savings, debt payments, card utilization and
# the top expense categories.
#
# The period is a calendar month (`month:`) or a pay cycle (`cycle:`, a
# PayCycle::Cycle — with a configured schedule the summary speaks cycles).
#
#   data = FinancialSummaryService.new(user: user, month: Time.zone.today).call
#   data[:expenses][:total]          # => BigDecimal
#   data[:expenses][:delta_pct]      # => Float | nil (nil without previous data)
class FinancialSummaryService
  def initialize(user:, month: nil, cycle: nil)
    @user = user
    if cycle
      @cycle = cycle
      @span = cycle.to_range
      @previous_span = PayCycle.containing(user, cycle.starts - 1.day).to_range
    else
      @month = month || Time.zone.today
      @span = @month.beginning_of_month..@month.end_of_month
      @previous_month = @month << 1
      @previous_span = @previous_month.beginning_of_month..@previous_month.end_of_month
    end
  end

  def call
    @expense_current = Expense.dashboard_summary(user: @user, range: @span)[:total_amount].abs
    @expense_previous = Expense.dashboard_summary(user: @user, range: @previous_span)[:total_amount].abs
    @income_current = Income.dashboard_summary(user: @user, range: @span)[:total_amount]
    @income_previous = Income.dashboard_summary(user: @user, range: @previous_span)[:total_amount]

    {
      month: @month,
      period_key: @cycle&.starts&.iso8601,
      period_label: @cycle&.label,
      income: { total: @income_current, previous: @income_previous, delta_pct: delta_pct(@income_current, @income_previous) },
      expenses: {
        total: @expense_current, previous: @expense_previous, delta_pct: delta_pct(@expense_current, @expense_previous),
        top_categories: top_categories
      },
      savings: {
        total: @income_current - @expense_current,
        pct_of_income: pct(@income_current - @expense_current, @income_current)
      },
      debt: {
        payments: debt_payments,
        utilization_pct: card_utilization
      }
    }
  end

  private

  def delta_pct(current, previous)
    return nil if previous.to_i.zero?

    ((current.to_d - previous.to_d) / previous.to_d * 100).round(1)
  end

  def pct(part, total)
    return nil if total.to_i.zero?

    (part.to_d / total.to_d * 100).round(1)
  end

  def top_categories
    by_category = Expense.dashboard_summary(user: @user, range: @span)[:by_category]
    return [] if by_category.blank?

    by_category.sort_by { |_, total| -total.abs }
               .first(4)
               .map do |name, total|
      { name: name, total: total.abs, share_pct: pct(total.abs, @expense_current) }
    end
  end

  # Debt payments are Payments toward credit cards/loans whose expense
  # (Transaction) falls within the period.
  def debt_payments
    Payment.joins(:expense)
           .where(payments: { user_id: @user.id })
           .where(transactions: { date: @span })
           .sum(:amount)
  end

  def card_utilization
    cards = @user.money_sources.active.where(kind: "credit_card").includes(:credit_account)
    limits = cards.filter_map { |card| card.credit_limit.to_i.positive? ? card.credit_limit.to_d : nil }
    return nil if limits.sum.zero?

    used = cards.sum(&:used_credit).to_d
    pct(used, limits.sum)
  end
end
