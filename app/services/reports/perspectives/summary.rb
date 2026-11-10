# frozen_string_literal: true

# Reports::Perspectives::Summary
# Short contextual reading of the selected period. Every sentence is chosen
# from the calculated totals and the comparison result; there are no fixed
# conclusions disconnected from the data.
#
# Methods: call
#
# Example: Reports::Perspectives::Summary.new(metrics:, comparison:).call
class Reports::Perspectives::Summary
  def initialize(metrics:, comparison:)
    @metrics = metrics
    @comparison = comparison
  end

  attr_reader :metrics, :comparison

  def call
    return I18n.t("reports.perspectives.summary.no_data") unless current_activity?

    [ balance_sentence, variation_sentence, partial_sentence ].compact.join(" ")
  end

  private

  def current_activity?
    income.positive? || expenses.positive?
  end

  def balance_sentence
    if income.positive? && balance.positive?
      I18n.t("reports.perspectives.summary.positive_balance", amount: currency(balance))
    elsif income.positive? && balance.negative?
      I18n.t("reports.perspectives.summary.negative_balance", amount: currency(balance.abs))
    elsif income.positive? && balance.zero?
      I18n.t("reports.perspectives.summary.balanced")
    elsif income.zero? && expenses.positive?
      I18n.t("reports.perspectives.summary.no_income")
    elsif expenses.zero?
      I18n.t("reports.perspectives.summary.no_expenses")
    end
  end

  def variation_sentence
    return I18n.t("reports.perspectives.summary.no_comparison") unless comparison[:available]
    return I18n.t("reports.perspectives.summary.no_expenses_comparison") if expenses.zero?

    pct = comparison[:delta_pct]
    return I18n.t("reports.perspectives.summary.no_variation") if pct.nil? || pct.zero?

    key = pct.positive? ? :increase : :decrease
    I18n.t("reports.perspectives.summary.#{key}",
           pct: percentage(pct.abs), amount: currency(comparison[:delta].abs),
           period: comparison_period)
  end

  def partial_sentence
    return nil unless comparison[:partial]

    I18n.t("reports.perspectives.summary.partial")
  end

  def comparison_period
    comparison[:partial] ? I18n.t("reports.perspectives.period_labels.previous_partial") :
                           I18n.t("reports.perspectives.period_labels.previous")
  end

  def income
    metrics[:income][:total].to_d
  end

  def expenses
    metrics[:expenses][:total].to_d
  end

  def balance
    metrics[:balance].to_d
  end

  def percentage(value)
    ActionController::Base.helpers.number_to_percentage(
      value, precision: 1, strip_insignificant_zeros: true
    )
  end

  def currency(value)
    MoneyFormat.currency(value)
  end
end
