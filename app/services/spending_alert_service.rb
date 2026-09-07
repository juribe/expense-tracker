# frozen_string_literal: true

# SpendingAlertService
# Evaluates whether a (user, category, month) now warrants a spending alert and
# reconciles the stored rows so deduplication holds: one alert per kind, per
# category, per month, inserted once and never re-fired, and removed when the
# condition no longer applies.
#
# Only the current month is evaluated (v1 scope); historical imports never
# flood the alert center. Budget alerts are inert until a Budget exists.
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
  end

  def call
    return if past_month?
    return if @category.nil?

    spent = CategorySpend.call(user: @user, category: @category, month: @month)
    expected = expected_kinds(spent)
    reconcile(expected)
  end

  private

  def past_month?
    @month.beginning_of_month != Time.zone.today.beginning_of_month
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

    previous = CategorySpend.call(user: @user, category: @category, month: @month.prev_month)
    previous.positive? && spent >= previous * (1 + SPENDING_INCREASE_PCT / 100.0)
  end

  def spending_increase_facts(spent)
    previous = CategorySpend.call(user: @user, category: @category, month: @month.prev_month)
    increase_pct = ((spent - previous) / previous * 100).round
    { pct: increase_pct, amount: spent, previous_amount: previous }
  end

  def budget_enabled?
    prefs = @user.alert_prefs
    prefs.budget_threshold_enabled? || prefs.budget_exceeded_enabled?
  end

  def reconcile(expected)
    month_str = @month.strftime("%Y-%m")
    expected_keys = expected.keys.map(&:to_s)

    existing = SpendingAlert.where(user_id: @user.id, category_id: @category.id, month: month_str)
    existing.find_each do |alert|
      alert.destroy! unless expected_keys.include?(alert.kind)
    end

    expected.each do |kind, facts|
      create_alert(kind, month_str, facts)
    end
  end

  def create_alert(kind, month_str, facts)
    SpendingAlert.create_or_find_by!(
      user_id: @user.id, category_id: @category.id, kind: kind, month: month_str
    ) do |alert|
      alert.pct = facts[:pct]
      alert.amount = facts[:amount]
      alert.previous_amount = facts[:previous_amount]
    end
  end
end
