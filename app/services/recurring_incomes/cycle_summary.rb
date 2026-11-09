# frozen_string_literal: true

# RecurringIncomes::CycleSummary
# Adapts the generic recurring-template aggregation to the income listing:
# monthly expected amount, pending receipts, money actually received in the
# selected cycle and the next pending income occurrence.
#
# Example: RecurringIncomes::CycleSummary.new(user:, period:).call[:received_total]
class RecurringIncomes::CycleSummary
  def initialize(user:, period:)
    @user = user
    @period = period
  end

  def call
    summary = RecurringTemplates::CycleSummary.new(
      user: user,
      period: period,
      kind: "income"
    ).call

    {
      monthly_expected: summary[:monthly_total],
      active_count: summary[:active_count],
      pending_count: summary[:pending_count],
      pending_total: summary[:pending_total],
      received_total: summary[:received_total],
      received_count: summary[:received_count],
      expected_count: summary[:expected_count],
      completion_percentage: summary[:completion_percentage],
      next_income: summary[:next_due]
    }
  end

  private

  attr_reader :user, :period
end
