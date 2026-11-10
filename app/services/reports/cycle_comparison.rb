# frozen_string_literal: true

# Reports::CycleComparison
# Period-over-period reading for a cycle balance. Completed cycles compare
# against the whole previous cycle; an in-progress cycle compares against the
# same elapsed days of the previous one so a partial month is never measured
# against a complete month.
#
# Methods: call
#
# Example: Reports::CycleComparison.new(user:, cycle:, current_balance:).call[:income]
class Reports::CycleComparison
  def initialize(user:, cycle:, current_balance:, filter: nil)
    @user = user
    @cycle = cycle
    @current_balance = current_balance
    @filter = filter
  end

  def call
    previous_balance = Reports::CycleBalances.new(user: user, cycles: [ previous_window ], filter: filter).call.first

    {
      previous_cycle: previous_cycle,
      previous_window: previous_window,
      same_elapsed_days: partial?,
      partial: partial?,
      income: comparison_for(:income_total, previous_balance),
      expense: comparison_for(:expense_total, previous_balance)
    }
  end

  private

  attr_reader :user, :cycle, :current_balance, :filter

  def previous_cycle
    @previous_cycle ||= PayCycle.previous(user, anchor: cycle.starts)
  end

  def previous_window
    @previous_window ||= if partial?
      elapsed = (Date.current - cycle.starts).to_i + 1
      starts = previous_cycle.starts
      ends = [ starts + elapsed - 1, previous_cycle.ends ].min
      PayCycle::Cycle.new(starts: starts, ends: ends)
    else
      previous_cycle
    end
  end

  def partial?
    Date.current.between?(cycle.starts, cycle.ends)
  end

  def comparison_for(metric, previous_balance)
    current = current_balance[metric].to_d
    previous = previous_balance[metric].to_d
    amount = current - previous

    {
      current: current,
      previous: previous,
      amount: amount,
      pct: previous.zero? ? nil : (amount / previous * 100).round(1),
      direction: direction(amount),
      base_available: previous.positive?
    }
  end

  def direction(amount)
    return :up if amount.positive?
    return :down if amount.negative?

    :flat
  end
end
