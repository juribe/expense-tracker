# frozen_string_literal: true

# PayCycle
# Financial-cycle engine: the user's financial month. A cycle always spans
# one month, opening on the user's `financial_cycle_start_day` (1..28) and
# closing the day before the next start. It never depends on how many
# incomes the user receives — two or five incomes share the same monthly
# cycle — and it is fully deterministic for any date.
#
# With start day 20 the cycle named "Octubre 2026" runs Oct 20th..Nov 19th:
# a bill paid on Nov 1st belongs to October's cycle (it is funded by
# October's pay). Labels follow the month the cycle STARTS in.
#
# The default start day (1) makes every cycle a plain calendar month, which
# keeps the historical behavior for users who never configure it.
#
# Periods persist as keys: the calendar month "YYYY-MM" for start day 1, or
# the cycle start ISO date ("2026-10-20") otherwise.
#
# Methods: containing, current, previous, back, cycles_between, period_for,
# key_range (Cycle#starts, Cycle#ends, Cycle#label, Cycle#to_range)
#
# Example: PayCycle.containing(user, Date.current) # => Cycle(starts: .., ends: ..)
class PayCycle
  # A concrete cycle. `starts` is inclusive (the start day) and `ends` is the
  # day before the next cycle's start day, also inclusive.
  Cycle = Struct.new(:starts, :ends, keyword_init: true) do
    def to_range
      starts..ends
    end

    # Named by the month the cycle starts in: "Octubre 2026".
    def label
      I18n.l(starts, format: "%B %Y")
    end

    # Optional range display: "Oct 20 – Nov 19".
    def range_label
      "#{I18n.l(starts, format: '%b %e').squeeze(' ').strip} – #{I18n.l(ends, format: '%b %e').squeeze(' ').strip}"
    end
  end

  class << self
    def containing(user, date = Date.current)
      date = date.to_date
      start_day = user.financial_cycle_start_day.to_i
      raise ArgumentError, "financial cycle start day must be between 1 and 28" unless start_day.between?(1, 28)

      # On/after the start day the cycle opens this month; before it, the
      # cycle opened last month. Start days never exceed 28, so every month
      # has its start day and no clamping is ever needed.
      starts = date.day >= start_day ? Date.new(date.year, date.month, start_day)
                                     : Date.new(date.year, date.month, start_day).prev_month
      Cycle.new(starts: starts, ends: starts.next_month - 1.day)
    end

    def current(user)
      containing(user, Date.current)
    end

    def previous(user, anchor: Date.current)
      back(user, 2, anchor: anchor).first
    end

    # The last `count` cycles ending with the one containing `anchor`, in
    # chronological order (oldest first).
    def back(user, count, anchor: Date.current)
      cycles = [ containing(user, anchor) ]
      (count - 1).times { cycles << containing(user, cycles.last.starts - 1.day) }
      cycles.reverse
    end

    # Every cycle overlapping the given range, in chronological order. A cycle
    # counts when it ends on or after the range begins (inclusive boundaries).
    def cycles_between(user, range)
      cycles = []
      cycle = containing(user, range.end)
      while cycle.ends >= range.begin
        cycles.unshift(cycle)
        cycle = containing(user, cycle.starts - 1.day)
      end
      cycles
    end

    # Canonical persisted period key + range for a date: the calendar month
    # ("YYYY-MM") without a configured schedule, or the pay cycle (key = its
    # start ISO date) when one is configured. Consumers (summary, dashboard,
    # cuadre) persist this key and resolve ranges back with key_range.
    def period_for(user, date = Date.current)
      date = date.to_date
      unless Reports::Period.cycles_enabled?(user)
        return [ date.strftime("%Y-%m"), date.beginning_of_month..date.end_of_month ]
      end

      cycle = containing(user, date)
      [ cycle.starts.iso8601, cycle.to_range ]
    end

    # Range for a persisted period key in either shape.
    def key_range(user, key)
      key = key.to_s
      return calendar_month_range(key) if key.match?(/\A\d{4}-\d{2}\z/)

      containing(user, Date.iso8601(key)).to_range
    end

    private

    def calendar_month_range(key)
      year, month = key.split("-").map(&:to_i)
      Date.new(year, month, 1).beginning_of_month..Date.new(year, month, 1).end_of_month
    end
  end
end
