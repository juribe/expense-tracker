# frozen_string_literal: true

# Reports::SavingsCapacity
# Read-only projection of the money that could remain at the end of a future
# financial cycle. It starts from recurring income and expenses (the same
# templates the cycle listings use), then optionally subtracts a percentage
# reserve for everyday expenses and the last closed cycle's variable spending.
#
# It never creates movements, assigns pockets or changes balances. The
# reference-cycle query reuses Reports::Filter#actual_expense_scope, so a
# debt payment (Expense carrying a Payment) is never counted twice, and
# recurring-linked expenses are excluded from the variable estimate.
#
# Methods: call, self.next_cycle, self.future_cycles, self.cycle_from_param
#
# Example: Reports::SavingsCapacity.new(user:, filter:, cycle:).call[:default_scenario]
class Reports::SavingsCapacity
  DEFAULT_PERCENTAGE = 30
  PERCENTAGES = (5..50).step(5).to_a.freeze
  FUTURE_CYCLES_LIMIT = 6

  class << self
    # The cycle immediately after the one containing `anchor`.
    def next_cycle(user, anchor: Date.current)
      current = PayCycle.containing(user, anchor)
      PayCycle.containing(user, current.ends + 1.day)
    end

    # Future cycles offered by the selector, nearest first.
    def future_cycles(user, count: FUTURE_CYCLES_LIMIT, anchor: Date.current)
      cycles = [ next_cycle(user, anchor: anchor) ]
      (count - 1).times { cycles << PayCycle.containing(user, cycles.last.ends + 1.day) }
      cycles
    end

    # Resolves the selector value. Only cycles offered by the report are
    # accepted; anything else falls back to the next future cycle.
    def cycle_from_param(user, raw, anchor: Date.current)
      cycles = future_cycles(user, anchor: anchor)
      return cycles.first if raw.blank?

      date = Date.iso8601(raw.to_s)
      cycles.find { |cycle| cycle.starts == date } || cycles.first
    rescue Date::Error, ArgumentError
      cycles.first
    end
  end

  def initialize(user:, filter:, cycle: nil, basic_reserve_enabled: true,
                 include_previous_expenses: true, basic_reserve_percentage: nil)
    @user = user
    @filter = filter
    @cycle = cycle || self.class.next_cycle(user)
    @basic_reserve_enabled = basic_reserve_enabled
    @include_previous_expenses = include_previous_expenses
    @percentage = normalize_percentage(basic_reserve_percentage)
  end

  def call
    {
      cycle: cycle,
      cycles: self.class.future_cycles(user),
      income_total: income_total,
      recurring_expense_total: recurring_expense_total,
      after_recurring_total: after_recurring_total,
      reference_cycle: reference_cycle,
      previous_variable_total: previous_variable_total,
      previous_variable_count: previous_variable_count,
      percentage: percentage,
      percentages: PERCENTAGES,
      basic_reserve_enabled: @basic_reserve_enabled,
      include_previous_expenses: @include_previous_expenses,
      scenarios: scenarios,
      default_scenario: default_scenario
    }
  end

  private

  attr_reader :user, :filter, :cycle, :percentage

  def income_total
    @income_total ||= recurring_total("income")
  end

  def recurring_expense_total
    @recurring_expense_total ||= recurring_total("expense")
  end

  # Active templates are expected once per cycle, exactly as the recurring
  # listings and the available-cycle report treat them. Summing the relation
  # directly avoids the per-template status queries in CycleSummary, which
  # this projection does not need.
  def recurring_total(kind)
    RecurringTemplate.for_user(user).where(kind: kind).active.sum(:amount).to_d
  end

  def after_recurring_total
    income_total - recurring_expense_total
  end

  # A future projection must not use the current, still-open cycle: its
  # variable spending is partial and would overstate the savings capacity.
  # Walk back to the most recent cycle that has already ended.
  def reference_cycle
    @reference_cycle ||= begin
      candidate = PayCycle.containing(user, cycle.starts - 1.day)
      candidate = PayCycle.containing(user, candidate.starts - 1.day) while candidate.ends >= Date.current
      candidate
    end
  end

  # Consumption spending only: Payment-linked expenses are debt repayments and
  # recurring-template transactions are commitments already represented by
  # their configuration. Transfers live in a separate model and never appear
  # here. The gmail/idempotency deduplication is enforced when records are
  # created, so no extra duplicate rule is invented.
  def previous_variable_scope
    filter.actual_expense_scope(reference_cycle.to_range)
          .where(recurring_template_id: nil)
          .where.not(source: "recurring_template")
  end

  def previous_variable_totals
    @previous_variable_totals ||= begin
      total, count = previous_variable_scope.pick(
        Arel.sql("COALESCE(ABS(SUM(transactions.amount)), 0)"),
        Arel.sql("COUNT(*)")
      )
      [ total.to_d, count.to_i ]
    end
  end

  def previous_variable_total
    previous_variable_totals.first
  end

  def previous_variable_count
    previous_variable_totals.last
  end

  # Every percentage/option combination is computed here so the frontend only
  # selects a value instead of repeating financial logic.
  def scenarios
    @scenarios ||= PERCENTAGES.flat_map do |candidate|
      reserve = (income_total * candidate / 100).round(2)

      [ true, false ].product([ true, false ]).map do |basic_enabled, include_previous|
        basic_amount = basic_enabled ? reserve : 0.to_d
        previous_amount = include_previous ? previous_variable_total : 0.to_d
        additional = basic_amount + previous_amount

        {
          percentage: candidate,
          basic_reserve_enabled: basic_enabled,
          include_previous: include_previous,
          basic_reserve: basic_amount,
          previous_variable: previous_amount,
          additional_total: additional,
          result: after_recurring_total - additional
        }
      end
    end
  end

  def default_scenario
    @default_scenario ||= scenarios.find do |scenario|
      scenario[:percentage] == percentage &&
        scenario[:basic_reserve_enabled] == @basic_reserve_enabled &&
        scenario[:include_previous] == @include_previous_expenses
    end
  end

  def normalize_percentage(value)
    number = value.to_i
    number = DEFAULT_PERCENTAGE if number <= 0
    number = [ [ number, PERCENTAGES.first ].max, PERCENTAGES.last ].min
    (number / 5.0).round * 5
  end
end
