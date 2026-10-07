# frozen_string_literal: true

require "test_helper"

# PayCycle — the user's financial month. Deterministic mapping from any date
# to its cycle given `financial_cycle_start_day`, with the nine documented
# cases: start day 1, start day 20, boundary days, multiple incomes sharing
# one cycle, calendar-length differences and year rollover.
class PayCycleTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Cycle User", email: "pay_cycle_test@example.com", password: "password123")
  end

  # 1) Start day 1: plain calendar months.
  test "start day 1 degenerates to calendar months" do
    @user.update!(financial_cycle_start_day: 1)

    cycle = PayCycle.containing(@user, Date.new(2026, 10, 6))

    assert_equal Date.new(2026, 10, 1), cycle.starts
    assert_equal Date.new(2026, 10, 31), cycle.ends
    assert_not @user.financial_cycles_enabled?
  end

  # 2) Start day 20: cycles named by their starting month.
  test "start day 20 names each cycle after its starting month" do
    @user.update!(financial_cycle_start_day: 20)

    september = PayCycle.containing(@user, Date.new(2026, 9, 25))
    october = PayCycle.containing(@user, Date.new(2026, 10, 25))

    assert_equal Date.new(2026, 9, 20)..Date.new(2026, 10, 19), september.to_range
    assert_match(/sep/i, september.label)
    assert_equal Date.new(2026, 10, 20)..Date.new(2026, 11, 19), october.to_range
    assert_match(/oct/i, october.label)
    assert @user.financial_cycles_enabled?
  end

  # 3) A date exactly on the start day opens the new cycle.
  test "a date on the start day belongs to the new cycle" do
    @user.update!(financial_cycle_start_day: 20)

    cycle = PayCycle.containing(@user, Date.new(2026, 10, 20))

    assert_equal Date.new(2026, 10, 20), cycle.starts
    assert_match(/oct/i, cycle.label)
  end

  # 4) A date before the start day belongs to the previous cycle.
  test "a date before the start day belongs to the previous cycle" do
    @user.update!(financial_cycle_start_day: 20)

    cycle = PayCycle.containing(@user, Date.new(2026, 10, 19))

    assert_equal Date.new(2026, 9, 20), cycle.starts
    assert_match(/sep/i, cycle.label)
  end

  # 5) A cycle with multiple incomes: cycles are never per payment.
  test "multiple incomes in a cycle map to the same cycle key" do
    # Spec example: start day 1, two incomes mid/late September → one cycle.
    @user.update!(financial_cycle_start_day: 1)
    first = PayCycle.period_for(@user, Date.new(2026, 9, 15)).first
    second = PayCycle.period_for(@user, Date.new(2026, 9, 30)).first
    assert_equal "2026-09", first
    assert_equal first, second

    # Same with a day-20 schedule: incomes Sep 21 and Oct 15 share the
    # cycle opened on Sep 20.
    @user.update!(financial_cycle_start_day: 20)
    assert_equal "2026-09-20", PayCycle.period_for(@user, Date.new(2026, 9, 21)).first
    assert_equal "2026-09-20", PayCycle.period_for(@user, Date.new(2026, 10, 15)).first
  end

  # 6) Expense and income inside the same cycle.
  test "expense and income in the same span belong to the same cycle" do
    @user.update!(financial_cycle_start_day: 20)

    expense_cycle = PayCycle.containing(@user, Date.new(2026, 10, 5))
    income_cycle = PayCycle.containing(@user, Date.new(2026, 9, 30))

    assert_equal income_cycle.starts, expense_cycle.starts
    assert_equal expense_cycle.ends, income_cycle.ends
  end

  # 7) The boundary day flips to the next cycle: 19/10 is September, 20/10 is
  # October.
  test "the boundary day splits adjacent cycles" do
    @user.update!(financial_cycle_start_day: 20)

    assert_match(/sep/i, PayCycle.containing(@user, Date.new(2026, 10, 19)).label)
    assert_match(/oct/i, PayCycle.containing(@user, Date.new(2026, 10, 20)).label)
  end

  # 8) Year rollover: December's cycle reaches into January.
  test "december's cycle crosses into january" do
    @user.update!(financial_cycle_start_day: 20)

    cycle = PayCycle.containing(@user, Date.new(2026, 12, 25))

    assert_equal Date.new(2026, 12, 20), cycle.starts
    assert_equal Date.new(2027, 1, 19), cycle.ends
    assert_match(/dic/i, cycle.label)
  end

  # 9) Month length differences: start days up to 28 fit every month, and the
  # cycle end stays inside the following month.
  test "start day 28 works in february" do
    @user.update!(financial_cycle_start_day: 28)

    cycle = PayCycle.containing(@user, Date.new(2027, 2, 10)) # 2027 is not a leap year

    assert_equal Date.new(2027, 1, 28), cycle.starts
    assert_equal Date.new(2027, 2, 27), cycle.ends
  end

  test "rejects start days beyond 28" do
    user = User.new(financial_cycle_start_day: 29)

    assert_not user.valid?
    assert_raises(ArgumentError) { PayCycle.containing(user, Date.current) }
  end

  test "current, previous and back walk cycles from an anchor" do
    @user.update!(financial_cycle_start_day: 20)

    cycles = PayCycle.back(@user, 3, anchor: Date.new(2026, 10, 6))
    assert_equal [ Date.new(2026, 7, 20), Date.new(2026, 8, 20), Date.new(2026, 9, 20) ],
                 cycles.map(&:starts)
    assert_equal Date.new(2026, 9, 20), PayCycle.previous(@user, anchor: Date.new(2026, 10, 25)).starts
  end

  test "cycles_between lists every cycle overlapping the range in order" do
    @user.update!(financial_cycle_start_day: 20)

    cycles = PayCycle.cycles_between(@user, Date.new(2026, 10, 1)..Date.new(2026, 11, 30))

    assert_equal [
      Date.new(2026, 9, 20)..Date.new(2026, 10, 19),
      Date.new(2026, 10, 20)..Date.new(2026, 11, 19),
      Date.new(2026, 11, 20)..Date.new(2026, 12, 19)
    ], cycles.map { |c| c.starts..c.ends }
  end

  test "period_for yields a calendar key without a configured cycle" do
    key, range = PayCycle.period_for(@user, Date.new(2026, 10, 6))

    assert_equal "2026-10", key
    assert_equal Date.new(2026, 10, 1)..Date.new(2026, 10, 31), range
  end

  test "period_for yields the cycle start as key with a configured cycle" do
    @user.update!(financial_cycle_start_day: 20)

    key, range = PayCycle.period_for(@user, Date.new(2026, 11, 2))

    assert_equal "2026-10-20", key
    assert_equal Date.new(2026, 10, 20)..Date.new(2026, 11, 19), range
  end

  test "key_range resolves back both key shapes" do
    @user.update!(financial_cycle_start_day: 20)

    assert_equal Date.new(2026, 10, 1)..Date.new(2026, 10, 31), PayCycle.key_range(@user, "2026-10")
    assert_equal Date.new(2026, 10, 20)..Date.new(2026, 11, 19), PayCycle.key_range(@user, "2026-10-20")
  end
end
