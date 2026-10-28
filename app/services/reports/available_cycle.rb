# frozen_string_literal: true

# Reports::AvailableCycle
# Available money for the current financial cycle: current cash/accounts,
# pending monthly expenses, remaining balance and days left in the cycle.
#
# Example: Reports::AvailableCycle.new(user: user).call
class Reports::AvailableCycle
  CURRENT_MONEY_KINDS = %w[account cash wallet].freeze

  attr_reader :user

  def initialize(user:)
    @user = user
  end

  def call
    cycle = PayCycle.current(user)
    current_money = current_money_total
    pending_expenses = pending_monthly_expenses(cycle)
    pending_total = pending_expenses.sum { |expense| expense[:missing] }
    {
      cycle: cycle,
      current_money: current_money,
      pending_expenses: pending_expenses,
      pending_total: pending_total,
      remaining: current_money - pending_total,
      days_remaining: days_remaining(cycle),
      total_days: total_days(cycle),
      elapsed_days: elapsed_days(cycle),
      progress_percent: progress_percent(cycle)
    }
  end

  private

  def current_money_total
    user.money_sources.active.where(kind: CURRENT_MONEY_KINDS).to_a.sum(&:balance).to_d
  end

  def pending_monthly_expenses(cycle)
    user.recurring_templates.active.where(kind: "expense").includes(:category).filter_map do |template|
      paid = template.paid_amount_for_period(cycle).to_d
      missing = template.amount.to_d - paid
      next if missing <= 0

      due_date = due_date_for(template, cycle)
      days_until_due = due_date && (due_date - Date.current).to_i
      {
        template: template,
        name: template.description.presence || template.category&.name,
        category: template.category&.name,
        due_date: due_date,
        days_until_due: days_until_due,
        original: template.amount.to_d,
        paid: paid,
        missing: missing,
        overdue: days_until_due&.negative? || false,
        due_today: days_until_due&.zero? || false,
        due_soon: days_until_due.present? && days_until_due.between?(1, 5)
      }
    end.sort_by { |expense| sort_key(expense) }
  end

  def due_date_for(template, cycle)
    return nil if template.payment_day.blank?

    day = [ template.payment_day.to_i, cycle.starts.end_of_month.day ].min
    date = Date.new(cycle.starts.year, cycle.starts.month, day)
    date += 1.month if date < cycle.starts
    return nil if date > cycle.ends

    date
  rescue ArgumentError
    nil
  end

  def sort_key(expense)
    [ expense[:due_date].nil? ? 1 : 0, expense[:due_date] || Date.new(9999, 12, 31) ]
  end

  def days_remaining(cycle)
    [ (cycle.ends - Date.current).to_i, 0 ].max
  end

  def total_days(cycle)
    (cycle.ends - cycle.starts + 1).to_i
  end

  def elapsed_days(cycle)
    value = (Date.current - cycle.starts + 1).to_i
    value = 0 if value.negative?
    value = total_days(cycle) if value > total_days(cycle)
    value
  end

  def progress_percent(cycle)
    total = total_days(cycle)
    return 0 if total.zero?

    (elapsed_days(cycle).to_f / total * 100).round
  end
end
