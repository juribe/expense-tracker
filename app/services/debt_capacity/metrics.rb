# frozen_string_literal: true

module DebtCapacity
  # Calculates monthly debt capacity without treating the target margin as free cash.
  class Metrics
    DEFAULT_TARGET_PERCENTAGE = 30.to_d
    DEFAULT_ALERT_PERCENTAGE = 40.to_d

    def initialize(income:, monthly_installments:, essential_expenses: nil,
                   target_percentage: DEFAULT_TARGET_PERCENTAGE, alert_percentage: DEFAULT_ALERT_PERCENTAGE)
      @income = income.to_d
      @monthly_installments = monthly_installments.to_d
      @essential_expenses = essential_expenses&.to_d
      @target_percentage = target_percentage.to_d
      @alert_percentage = alert_percentage.to_d
    end

    def call
      return unavailable_result unless @income.positive?

      target_amount = @income * @target_percentage / 100
      alert_amount = @income * @alert_percentage / 100
      {
        monthly_income: @income,
        monthly_installments: @monthly_installments,
        debt_ratio: (@monthly_installments / @income * 100).round(1),
        target_percentage: @target_percentage,
        alert_percentage: @alert_percentage,
        target_amount: target_amount,
        alert_amount: alert_amount,
        essential_expenses: @essential_expenses,
        essential_expenses_percentage: essential_expenses_percentage,
        available_margin: [ target_amount - @monthly_installments, 0 ].max,
        excess_over_target: [ @monthly_installments - target_amount, 0 ].max,
        excess_over_alert: [ @monthly_installments - alert_amount, 0 ].max,
        financial_pressure: financial_pressure,
        status: status_for(@monthly_installments / @income * 100)
      }
    end

    private

    def unavailable_result
      {
        monthly_income: @income,
        monthly_installments: @monthly_installments,
        debt_ratio: nil,
        target_percentage: @target_percentage,
        alert_percentage: @alert_percentage,
        target_amount: nil,
        alert_amount: nil,
        essential_expenses: @essential_expenses,
        essential_expenses_percentage: nil,
        available_margin: nil,
        excess_over_target: nil,
        excess_over_alert: nil,
        financial_pressure: nil,
        status: :income_required
      }
    end

    def financial_pressure
      return nil unless @essential_expenses

      @income - @monthly_installments - @essential_expenses
    end

    def essential_expenses_percentage
      return nil unless @essential_expenses

      (@essential_expenses / @income * 100).round(1)
    end

    def status_for(ratio)
      return :healthy if ratio <= @target_percentage
      return :precaution if ratio <= @alert_percentage

      :elevated
    end
  end
end
