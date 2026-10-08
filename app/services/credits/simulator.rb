# frozen_string_literal: true

module Credits
  # Simulator
  # Runs the Colombian extra-payment strategies against a credit projection.
  # Every result comes from the amortization engine:
  #
  #   reduce_term          · abono a capital, la cuota se conserva, el plazo baja
  #   reduce_installment   · abono a capital, el plazo se conserva, la cuota
  #                          se recalcula (anualidad + seguro/cargos intactos)
  #   prepay_installments  · adelanto de cuotas a valor facial. NO reduce
  #                          capital: ahorro de interés $0, beneficio = cuotas
  #                          futuras sin pago (flujo liberado)
  #   target_payoff        · búsqueda binaria del extra requerido por cuota
  #                          para terminar N cuotas antes
  #
  # Strategies are reported both flat (for the saved-scenario views) and as
  # current/new impact blocks for the strategy comparison.
  #
  # Methods: run
  class Simulator
    STRATEGIES = %w[reduce_term reduce_installment prepay_installments target_payoff].freeze
    LEGACY_STRATEGIES = { "one_time_extra" => "reduce_term", "recurring_extra" => "reduce_term" }.freeze

    def self.run(projection:, strategy:, params:)
      new(projection, strategy, params).run
    end

    def initialize(projection, strategy, params)
      @projection = projection
      @strategy = LEGACY_STRATEGIES.fetch(strategy, strategy)
      @params = (params || {}).stringify_keys
      # Legacy recurring extras repeated every period by default.
      @params["repeat_every"] = 1 if strategy == "recurring_extra" && !@params.key?("repeat_every")
    end

    def run
      case @strategy
      when "prepay_installments" then run_prepay
      when "reduce_installment" then run_reduce_installment
      when "target_payoff" then run_target_payoff
      else run_reduce_term
      end
    end

    private

    # --------------------------------------------------------- reduce_term
    def run_reduce_term
      result = rebuilt_schedule(extras: term_extras)
      results = common_results(result)
      results["strategy"] = "reduce_term"
      results["new_installment"] = money(base_installment)
      results["reduction"] = "0.0"
      results["balance_after"] = money(balance - result.extra_cash)
      results["repeat_every"] = repeat_every if @params["repeat_every"].present?
      results
    end

    # -------------------------------------------------- reduce_installment
    # One-shot: run the first periods at the full installment (extra applied),
    # then amortize the remaining balance over the remaining term with a
    # recalculated (annuity) installment. Insurance and other charges are
    # added untouched — they are never recomputed downward.
    def run_reduce_installment
      split = after_period
      term = baseline_installments
      return run_reduce_term if split >= term

      phase1 = Credits::Amortization::ScheduleBuilder.build(
        **schedule_options(balance, base_installment), extras: one_time_extras, cap: split
      )
      balance_after_extra = phase1.final_balance
      return run_reduce_term if balance_after_extra <= 0

      remaining = term - split
      new_installment = annuity_installment(balance_after_extra, remaining) + insurance + other
      phase2 = Credits::Amortization::ScheduleBuilder.build(
        **schedule_options(balance_after_extra, new_installment).merge(
          start_installment_number: start_installment_number + split,
          first_payment_date: Credits::Amortization::Period.advance(phase1.rows.last.date, frequency)
        ),
        cap: remaining
      )
      combined = Credits::Amortization::Result.new(
        rows: phase1.rows + phase2.rows,
        truncated: phase1.truncated? || phase2.truncated?,
        reason: phase1.reason || phase2.reason,
        extra_cash: phase1.extra_cash,
        final_balance: phase2.final_balance
      )

      results = common_results(combined)
      results["strategy"] = "reduce_installment"
      results["new_installment"] = money(new_installment)
      results["reduction"] = money(base_installment - new_installment)
      results["balance_after"] = money(balance - combined.extra_cash)
      results
    end

    # -------------------------------------------------- prepay_installments
    # The amount covers future installments at face value (principal +
    # interest + insurance + other). The next installment falls due only
    # after the covered ones: the schedule itself does not change.
    def run_prepay
      installment_total = base_installment + insurance + other
      covered = installment_total.positive? ? (amount / installment_total).floor : 0
      covered = [ covered, baseline_installments ].min
      remainder = amount - covered * installment_total

      {
        "strategy" => "prepay_installments",
        "current" => current_block,
        "new" => current_block,
        "installments" => baseline_installments,
        "installments_eliminated" => 0,
        "payoff_date" => baseline_payoff_date,
        "final_installment_number" => baseline_last_number,
        "future_interest" => money(baseline_interest),
        "baseline_interest" => money(baseline_interest),
        "interest_saved" => "0.0",
        "extra_cash" => money(amount),
        "installment_amount" => money(base_installment),
        "new_installment" => money(base_installment),
        "reduction" => "0.0",
        "installments_covered" => covered,
        "months_without_payment" => covered,
        "freed_cash" => money(freed_cash(covered, remainder, installment_total)),
        "partial_installment" => remainder.positive?,
        "balance_before" => money(balance),
        "balance_after" => money(balance),
        "future_insurance" => money(baseline_insurance),
        "future_other" => money(baseline_other),
        "insurance_impact" => "0.0",
        "other_impact" => "0.0"
      }
    end

    def freed_cash(covered, remainder, installment_total)
      covered * installment_total + (covered.positive? ? remainder : 0)
    end

    # ------------------------------------------------------- target_payoff
    def run_target_payoff
      target_installments = baseline_installments - target_earlier.to_i
      required = required_extra_for(target_installments)

      result = rebuilt_schedule(extras: recurring_extras(required))
      results = common_results(result)
      results["strategy"] = "target_payoff"
      results["required_extra"] = money(required)
      results["new_total_payment"] = money(base_installment + required)
      results
    end

    # ------------------------------------------------------------ shared
    def common_results(result)
      {
        "current" => current_block,
        "new" => {
          "installment" => nil,
          "remaining_installments" => result.installments,
          "payoff_date" => result.payoff_date&.iso8601,
          "future_interest" => money(result.future_interest),
          "future_insurance" => money(result.future_insurance),
          "future_other" => money(result.future_other),
          "total_remaining" => money(result.future_total)
        },
        "installments" => result.installments,
        "installments_eliminated" => baseline_installments - result.installments,
        "payoff_date" => result.payoff_date&.iso8601,
        "final_installment_number" => result.last_installment_number,
        "future_interest" => money(result.future_interest),
        "baseline_interest" => money(baseline_interest),
        "interest_saved" => money(result.interest_saved_against(baseline_interest)),
        "extra_cash" => money(result.extra_cash),
        "installment_amount" => money(base_installment),
        "future_insurance" => money(result.future_insurance),
        "future_other" => money(result.future_other),
        "insurance_impact" => money(result.future_insurance - baseline_insurance),
        "other_impact" => money(result.future_other - baseline_other),
        "balance_before" => money(balance)
      }
    end

    def current_block
      {
        "installment" => money(base_installment),
        "remaining_installments" => baseline_installments,
        "payoff_date" => baseline_payoff_date,
        "future_interest" => money(baseline_interest),
        "future_insurance" => money(baseline_insurance),
        "future_other" => money(baseline_other),
        "total_remaining" => money(baseline_total)
      }
    end

    def required_extra_for(target_installments)
      target = [ target_installments, 1 ].max
      low = 0.to_d
      high = balance

      while (high - low) > 0.005
        mid = (low + high) / 2
        if rebuilt_schedule(extras: recurring_extras(mid)).installments <= target
          high = mid
        else
          low = mid
        end
      end

      required = high.round(2, BigDecimal::ROUND_UP)
      required += 0.01 while rebuilt_schedule(extras: recurring_extras(required)).installments > target
      required
    end

    def rebuilt_schedule(extras: {})
      Credits::Amortization::ScheduleBuilder.build(
        **schedule_options(balance, base_installment), extras: extras
      )
    end

    def schedule_options(balance_value, installment_value)
      {
        balance: balance_value,
        periodic_rate: periodic_rate,
        installment_amount: installment_value,
        insurance: insurance,
        other: other,
        start_installment_number: start_installment_number,
        first_payment_date: next_payment_date,
        frequency: frequency
      }
    end

    def term_extras
      if @params["repeat_every"].present?
        recurring_extras(amount)
      else
        one_time_extras
      end
    end

    def one_time_extras
      { one_time: { after_period: after_period, amount: amount } }
    end

    def recurring_extras(value)
      { recurring: {
        start_period: after_period,
        every_n_periods: repeat_every,
        amount: value
      } }
    end

    def repeat_every
      [ @params["repeat_every"].to_i, 1 ].max
    end

    def after_period
      (@params["after_period"] || 1).to_i
    end

    def amount
      BigDecimal(MoneyFormat.normalize(@params["amount"]).to_s)
    rescue ArgumentError, TypeError
      0.to_d
    end

    def target_earlier
      @params["months_earlier"].present? ? @params["months_earlier"].to_i : nil
    end

    # ------------------------------------------------------------ baseline
    def baseline_rows
      @baseline_rows ||= @projection.future_rows
    end

    def baseline_installments
      baseline_rows.size
    end

    def baseline_interest
      @baseline_interest ||= sum_rows("interest")
    end

    def baseline_insurance
      @baseline_insurance ||= sum_rows("insurance")
    end

    def baseline_other
      @baseline_other ||= sum_rows("other")
    end

    def baseline_total
      @baseline_total ||= sum_rows("total_payment")
    end

    def sum_rows(key)
      baseline_rows.reduce(0.to_d) { |total, row| total + row[key].to_d }
    end

    def baseline_payoff_date
      baseline_rows.last&.fetch("date")
    end

    def baseline_last_number
      baseline_rows.last&.fetch("installment_number")
    end

    def balance
      @balance ||= baseline_rows.first&.fetch("opening_balance", 0)&.to_d.to_f.to_d || 0.to_d
    end

    def periodic_rate
      BigDecimal(@projection.inputs["periodic_rate"].to_s)
    end

    def base_installment
      @base_installment ||= @projection.inputs["installment_amount"].to_d
    end

    def insurance
      (@projection.inputs["latest_insurance"] || 0).to_d
    end

    def other
      (@projection.inputs["latest_other"] || 0).to_d
    end

    def start_installment_number
      @projection.inputs["start_installment_number"].to_i
    end

    def next_payment_date
      Date.parse(@projection.inputs["next_payment_date"])
    end

    def frequency
      @projection.inputs["payment_frequency"]
    end

    def annuity_installment(balance_value, periods)
      rate = periodic_rate.to_f
      payment = balance_value.to_f * rate / (1 - (1 + rate)**-periods)
      payment.round(2).to_d
    end

    def money(value)
      value.to_d.round(2).to_s("F")
    rescue NoMethodError, TypeError
      "0.0"
    end
  end
end
