# frozen_string_literal: true

# RecurringExpenses::CycleSummary
# Adapts the generic recurring-template aggregation to the expense listing:
# monthly commitment, pending payments, completed payments and the next
# pending due date.
#
# Example: RecurringExpenses::CycleSummary.new(user:, period:).call[:pending_total]
class RecurringExpenses::CycleSummary
  def self.expected_date(template, period)
    RecurringTemplates::CycleSummary.expected_date(template, period)
  end

  def self.period_range(period)
    RecurringTemplates::CycleSummary.period_range(period)
  end

  def initialize(user:, period:)
    @user = user
    @period = period
  end

  def call
    summary = RecurringTemplates::CycleSummary.new(
      user: user,
      period: period,
      kind: "expense",
      include_received_total: false
    ).call

    {
      monthly_commitment: summary[:monthly_total],
      active_count: summary[:active_count],
      pending_count: summary[:pending_count],
      pending_total: summary[:pending_total],
      paid_count: summary[:received_count],
      expected_count: summary[:expected_count],
      completion_percentage: summary[:completion_percentage],
      next_due: summary[:next_due]
    }
  end

  private

  attr_reader :user, :period
end
