# frozen_string_literal: true

module DebtCapacity
  # Simulates a one-time payment against one selected debt.
  class Comparison
    MODES = %w[reduce_term reduce_installment].freeze
    DEFAULT_AMOUNT = 1_000_000.to_d
    DEFAULT_REVOLVING_INSTALLMENTS = 48

    def initialize(debts:, debt_id: nil, amount: DEFAULT_AMOUNT, mode: "reduce_term", installment_count: nil)
      @debts = debts
      @debt_id = debt_id
      @amount = amount.to_d
      @mode = MODES.include?(mode.to_s) ? mode.to_s : "reduce_term"
      @installment_count = normalize_installment_count(installment_count)
    end

    def call
      debt = selected_debt
      return unavailable_result unless debt

      baseline = baseline_schedule(debt)
      return unavailable_result(debt) unless baseline

      payment = [ @amount, debt[:balance].to_d ].min
      simulated = simulated_schedule(debt, payment, baseline)
      return unavailable_result(debt) unless simulated

      current = values_for(debt, baseline, current_installment(debt), debt[:balance])
      after = values_for(debt, simulated[:schedule], simulated[:installment], debt[:balance] - payment)
      {
        available: true,
        selected_debt: { id: debt[:id], name: debt[:name], balance: debt[:balance] },
        amount: payment,
        mode: mode_for(debt),
        installment_count: revolving?(debt) ? revolving_installment_count : nil,
        current: current,
        after: after,
        balance_reduction: payment,
        interest_saving: [ current[:future_interest] - after[:future_interest], 0.to_d ].max.round(2)
      }
    end

    private

    def selected_debt
      candidates = simulatable_debts
      return candidates.find { |debt| debt[:id].to_s == @debt_id.to_s } if @debt_id.present?

      candidates.max_by { |debt| [ debt[:annual_rate].to_d, debt[:monthly_interest].to_d ] }
    end

    def simulatable_debts
      @debts.select do |debt|
        debt[:balance].to_d.positive? && debt[:annual_rate].present? && debt[:monthly_installment].to_d.positive?
      end
    end

    def schedule_for(debt, balance: debt[:balance], installment: baseline_installment(debt), extras: {}, cap: nil)
      Credits::Amortization::ScheduleBuilder.build(
        balance: balance,
        periodic_rate: periodic_rate_for(debt),
        installment_amount: installment,
        insurance: debt[:insurance_amount].to_d,
        other: debt[:other_amount].to_d,
        first_payment_date: Date.current,
        frequency: debt[:payment_frequency].presence || "monthly",
        extras: extras,
        cap: cap || Credits::Amortization::ScheduleBuilder::DEFAULT_CAP
      )
    rescue ArgumentError, TypeError, ZeroDivisionError
      nil
    end

    def baseline_schedule(debt)
      return schedule_for(debt) unless revolving?(debt)

      schedule_for(debt, installment: annuity_installment(debt, debt[:balance], revolving_installment_count),
                   cap: revolving_installment_count)
    end

    def simulated_schedule(debt, payment, baseline)
      return { schedule: baseline, installment: baseline_installment(debt) } if payment.zero?

      return revolving_schedule(debt, payment) if revolving?(debt)

      if @mode == "reduce_installment"
        reduce_installment_schedule(debt, payment, baseline)
      else
        { schedule: schedule_for(debt, extras: { one_time: { after_period: 1, amount: payment } }),
          installment: baseline_installment(debt) }
      end
    end

    def revolving_schedule(debt, payment)
      balance = debt[:balance].to_d - payment
      installment = annuity_installment(debt, balance, revolving_installment_count)
      { schedule: schedule_for(debt, balance: balance, installment: installment, cap: revolving_installment_count),
        installment: installment }
    end

    def reduce_installment_schedule(debt, payment, baseline)
      first_phase = schedule_for(debt, extras: { one_time: { after_period: 1, amount: payment } }, cap: 1)
      return unless first_phase

      balance_after_payment = first_phase.final_balance
      remaining = [ baseline.installments - 1, 1 ].max
      installment = annuity_installment(debt, balance_after_payment, remaining)
      second_phase = schedule_for(debt, balance: balance_after_payment, installment: installment, cap: remaining)
      return unless second_phase

      combined = Credits::Amortization::Result.new(
        rows: first_phase.rows + second_phase.rows,
        truncated: first_phase.truncated? || second_phase.truncated?,
        reason: first_phase.reason || second_phase.reason,
        extra_cash: first_phase.extra_cash,
        final_balance: second_phase.final_balance
      )
      { schedule: combined, installment: installment }
    end

    def annuity_installment(debt, balance, periods)
      rate = periodic_rate_for(debt).to_f
      base = rate.zero? ? balance.to_d / periods : balance.to_f * rate / (1 - (1 + rate)**-periods)
      base.round(2).to_d + debt[:insurance_amount].to_d + debt[:other_amount].to_d
    end

    def values_for(debt, schedule, installment, balance)
      {
        balance: [ balance.to_d, 0.to_d ].max,
        installment: installment,
        remaining_installments: schedule.installments,
        future_interest: schedule.future_interest
      }
    end

    def baseline_installment(debt)
      debt[:monthly_installment].to_d
    end

    def current_installment(debt)
      return baseline_installment(debt) unless revolving?(debt)

      annuity_installment(debt, debt[:balance], revolving_installment_count)
    end

    def mode_for(debt)
      revolving?(debt) ? "reduce_installment" : @mode
    end

    def revolving?(debt)
      debt[:sub_kind].to_s == "revolving"
    end

    def revolving_installment_count
      @installment_count || DEFAULT_REVOLVING_INSTALLMENTS
    end

    def normalize_installment_count(value)
      return nil if value.blank?

      count = value.to_i
      count.positive? ? count : nil
    end

    def periodic_rate_for(debt)
      Credits::Rate::PeriodConverter.call(
        rate: debt[:annual_rate],
        rate_type: debt[:interest_rate_type].presence || "effective_annual",
        frequency: debt[:payment_frequency].presence || "monthly"
      )
    end

    def unavailable_result(debt = nil)
      { available: false, selected_debt: debt && { id: debt[:id], name: debt[:name], balance: debt[:balance] },
        amount: 0.to_d, mode: debt ? mode_for(debt) : @mode, installment_count: debt && revolving?(debt) ? revolving_installment_count : nil,
        current: {}, after: {}, balance_reduction: 0.to_d, interest_saving: 0.to_d }
    end
  end
end
