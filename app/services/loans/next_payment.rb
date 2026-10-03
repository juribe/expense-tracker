# frozen_string_literal: true

# Loans::NextPayment
# Best-effort next payment date for a loan. Prefers a scheduled recurring
# template (payment day); otherwise derives the date from the loan's start
# date, payment frequency and installments paid. Returns nil when it cannot
# be known, so callers show "Sin fecha" instead of a fabricated value.
#
# Methods: date (alias call)
#
# Example: Loans::NextPayment.call(mortgage) # => Date or nil
class Loans::NextPayment
  PERIOD_ADVANCE = { "weekly" => 7, "biweekly" => 14, "monthly" => 1.month, "quarterly" => 3.months }.freeze

  def self.call(loan)
    new(loan).date
  end

  def initialize(loan)
    @loan = loan
  end

  def date
    template_payment_day || derived_payment_date
  end

  private

  attr_reader :loan

  def template_payment_day
    template = loan.recurring_templates.active.order(:payment_day).first
    return nil unless template&.payment_day

    next_day_of_month(template.payment_day)
  end

  def next_day_of_month(day)
    today = Date.current
    candidate = Date.new(today.year, today.month, day.to_i)
    candidate = candidate.next_month if candidate < today
    candidate
  rescue ArgumentError, TypeError
    nil
  end

  def derived_payment_date
    return nil if loan.start_date.blank? || loan.payment_frequency.blank?

    period = PERIOD_ADVANCE[loan.payment_frequency]
    return nil if period.nil?

    paid = loan.credit_account&.installments_paid.to_i
    current = loan.start_date + (period * paid)
    current = current + period if current < Date.current
    current
  end
end
