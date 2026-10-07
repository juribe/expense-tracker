# frozen_string_literal: true

# SpendingAlertService
# Evaluates whether a (user, category, period) now warrants a spending alert
# and reconciles the stored rows so deduplication holds: one alert per kind,
# per category, per period, inserted once and never re-fired, and removed when
# the condition no longer applies.
#
# The period is the user's configured pay cycle (naming and grouping follow
# PayCycle) or the plain calendar month without a schedule. The dedup key
# stored in SpendingAlert.month is that period key: "YYYY-MM" or the cycle
# start ISO date ("2026-09-20").
#
# Only the period containing today is evaluated (v1 scope); historical
# imports never flood the alert center. Budget alerts are inert until a
# Budget exists.
#
# Example: SpendingAlertService.call(user: user, category: category, month: Time.zone.today)
class SpendingAlertService
  BUDGET_THRESHOLD_PCT = 80
  BUDGET_EXCEEDED_PCT = 100
  SPENDING_INCREASE_PCT = 35

  def self.call(user:, category:, month:)
    new(user: user, category: category, month: month).call
  end

  def initialize(user:, category:, month:)
    @user = user
    @category = category
    @month = month
    resolve_period
  end

  def call
    return if past_period?
    return if @category.nil?

    spent = CategorySpend.call(user: @user, category: @category, range: @span)
    expected = expected_kinds(spent)
    reconcile(expected)
  end

  private

  # The period the expense's date belongs to: a pay cycle (key = cycle start
  # ISO date) when the user configured paydays, the calendar month otherwise.
  def resolve_period
    @period_key, @span = PayCycle.period_for(@user, @month)
    @cycle = calendar_month_key? ? nil : PayCycle.containing(@user, Date.iso8601(@period_key))
  end

  def calendar_month_key?
    @period_key.match?(/\A\d{4}-\d{2}\z/)
  end

  # Only the current period (the one containing today) is reconciled; every
  # other past/future period is skipped so history never floods the center.
  def past_period?
    @period_key != PayCycle.period_for(@user, Time.zone.today).first
  end

  def expected_kinds(spent)
    kinds = {}
    kinds.merge!(budget_kind(spent)) if budget_enabled?
    kinds[:spending_increase] = spending_increase_facts(spent) if spending_increase_expected?(spent)
    kinds
  end

  def budget_kind(spent)
    budget = @user.budgets.find_by(category_id: @category.id)
    return {} unless budget && budget.monthly_amount.to_d.positive?

    pct = spent / budget.monthly_amount.to_d * 100
    if pct >= BUDGET_EXCEEDED_PCT
      { budget_exceeded: budget_facts(spent, pct) }
    elsif pct >= BUDGET_THRESHOLD_PCT
      { budget_threshold: budget_facts(spent, pct) }
    else
      {}
    end
  end

  def budget_facts(spent, pct)
    { pct: pct.round, amount: spent, previous_amount: nil }
  end

  def spending_increase_expected?(spent)
    return false unless @user.alert_prefs.spending_increase_enabled?

    previous_spend.positive? && spent >= previous_spend * (1 + SPENDING_INCREASE_PCT / 100.0)
  end

  def spending_increase_facts(spent)
    increase_pct = ((spent - previous_spend) / previous_spend * 100).round
    { pct: increase_pct, amount: spent, previous_amount: previous_spend }
  end

  # The period right before the evaluated one: the previous pay cycle with a
  # schedule, the previous calendar month otherwise.
  def previous_spend
    @previous_spend ||=
      if @cycle
        span = PayCycle.containing(@user, @cycle.starts - 1.day).to_range
        CategorySpend.call(user: @user, category: @category, range: span)
      else
        CategorySpend.call(user: @user, category: @category, month: @month.prev_month)
      end
  end

  def budget_enabled?
    prefs = @user.alert_prefs
    prefs.budget_threshold_enabled? || prefs.budget_exceeded_enabled?
  end

  def reconcile(expected)
    expected_keys = expected.keys.map(&:to_s)

    existing = SpendingAlert.where(user_id: @user.id, category_id: @category.id, month: @period_key)
    existing.find_each do |alert|
      alert.destroy! unless expected_keys.include?(alert.kind)
    end

    expected.each do |kind, facts|
      create_alert(kind, facts)
    end
  end

  def create_alert(kind, facts)
    SpendingAlert.create_or_find_by!(
      user_id: @user.id, category_id: @category.id, kind: kind, month: @period_key
    ) do |alert|
      alert.pct = facts[:pct]
      alert.amount = facts[:amount]
      alert.previous_amount = facts[:previous_amount]
    end
  end
end
