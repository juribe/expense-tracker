# frozen_string_literal: true

module DebtCapacity
  # Builds the read-only debt-capacity snapshot from MoneySource and transactions.
  class Overview
    attr_reader :user, :month

    def initialize(user:, month: Date.current, target_percentage: nil, alert_percentage: nil, comparison_options: {})
      @user = user
      @month = month
      @target_percentage = target_percentage || user.debt_capacity_target_percentage
      @alert_percentage = alert_percentage || user.debt_capacity_alert_percentage
      @comparison_options = comparison_options
    end

    def call
      debts = debt_rows
      installments = debts.filter_map { |debt| debt[:monthly_installment] }.sum
      income = monthly_income_reference
      essential_expenses = Expense.for_user(user).in_month(month).sum(:amount).abs.to_d
      metrics = Metrics.new(income: income, monthly_installments: installments,
                            essential_expenses: essential_expenses,
                            target_percentage: @target_percentage, alert_percentage: @alert_percentage).call
      summary = metrics.merge(
        total_debt: debts.filter_map { |debt| debt[:balance] }.sum,
        monthly_interest: debts.filter_map { |debt| debt[:monthly_interest] }.sum,
        monthly_installments: installments,
        interest_available: debts.any? { |debt| debt[:monthly_interest].present? }
      )
      {
        debts: debts,
        summary: summary,
        metrics: metrics,
        recommendations: Recommendations.new(debts: debts, monthly_income: income).call,
        comparison: Comparison.new(debts: debts, **@comparison_options).call
      }
    end

    private

    def debt_rows
      user.money_sources.active.where(kind: %w[credit_card loan]).includes(:credit_account).order(:name).map do |source|
        account = source.credit_account
        balance = debt_balance(source)
        rate = account&.interest_rate&.to_d
        {
          id: source.id,
          name: source.name,
          kind: source.kind,
          institution: source.institution_name,
          type: debt_type(source),
          sub_kind: source.sub_kind,
          balance: balance,
          monthly_installment: account&.installment_amount&.to_d,
          annual_rate: rate,
          interest_rate_type: account&.interest_rate_type,
          payment_frequency: account&.payment_frequency.presence || "monthly",
          insurance_amount: 0.to_d,
          other_amount: 0.to_d,
          installment_count: account&.installment_count,
          interest_rate_label: source.interest_rate_label,
          monthly_interest: estimated_interest(balance, rate, account&.interest_rate_type),
          status: debt_status(source),
          credit_limit: source.credit_card? ? source.credit_limit&.to_d : nil,
          used_credit: source.credit_card? ? source.used_credit.to_d : nil,
          available_credit: source.credit_card? ? source.available_credit&.to_d : nil,
          detail_path: Rails.application.routes.url_helpers.money_source_credits_path(source)
        }
      end
    end

    def monthly_income_reference
      RecurringTemplate.for_user(user).active.income.sum do |template|
        case template.frequency
        when "weekly" then template.amount.to_d * 52 / 12
        when "biweekly" then template.amount.to_d * 26 / 12
        when "quarterly" then template.amount.to_d / 3
        else template.amount.to_d
        end
      end.to_d
    end

    def debt_type(source)
      return "Tarjeta de crédito" if source.credit_card?
      return "Crédito rotativo" if source.revolving?

      source.sub_kind.presence || "Crédito"
    end

    def debt_balance(source)
      return nil unless source.debt?
      return source.used_credit.to_d if source.credit_card? || source.revolving?

      source.outstanding_balance&.to_d || [ -source.balance, 0 ].max
    end

    def estimated_interest(balance, rate, rate_type)
      return nil unless balance && rate

      monthly_rate = case rate_type
      when "monthly" then rate / 100
      when "nominal_annual" then rate / 12 / 100
      else (1 + rate / 100)**(1.0 / 12) - 1
      end
      (balance * monthly_rate).round(2)
    end

    def debt_status(source)
      due_day = source.payment_due_day
      return :current unless due_day && Date.current.day > due_day && source.payments.where(date: month.beginning_of_month..month.end_of_month).none?

      :at_risk
    end
  end
end
