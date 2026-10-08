# frozen_string_literal: true

module Credits
  # Simulator
  # Runs "what-if" extra principal payments against a credit projection's
  # schedule. Every result comes from the amortization engine — one-time
  # extras, recurring extras (every N periods) and a target-payoff search
  # for the extra needed to finish N periods earlier.
  #
  # Methods: run
  #
  # Example:
  #   Credits::Simulator.run(projection: projection, kind: "one_time_extra",
  #                          params: { "amount" => "300", "after_period" => 2 })
  class Simulator
    KINDS = %w[one_time_extra recurring_extra target_payoff].freeze

    def self.run(projection:, kind:, params:)
      new(projection, kind, params).run
    end

    def initialize(projection, kind, params)
      @projection = projection
      @kind = kind
      @params = (params || {}).stringify_keys
    end

    def run
      case @kind
      when "target_payoff" then run_target_payoff
      else run_extra_payment
      end
    end

    private

    def run_extra_payment
      result = rebuilt_schedule(extras: extras)
      reduce_term_results(result).merge("reduce_installment" => reduce_installment_alternative(result))
    end

    def run_target_payoff
      target_installments = baseline_installments - target_earlier.to_i
      required = required_extra_for(target_installments)

      result = rebuilt_schedule(extras: recurring_extras(required))
      results = reduce_term_results(result)
      results["required_extra"] = money(required)
      results["new_total_payment"] = money(base_installment + required)
      results
    end

    def reduce_term_results(result)
      {
        "installments" => result.installments,
        "installments_eliminated" => baseline_installments - result.installments,
        "payoff_date" => result.payoff_date&.iso8601,
        "final_installment_number" => result.last_installment_number,
        "future_interest" => money(result.future_interest),
        "baseline_interest" => money(baseline_interest),
        "interest_saved" => money(result.interest_saved_against(baseline_interest)),
        "extra_cash" => money(result.extra_cash),
        "installment_amount" => money(base_installment)
      }
    end

    # Alternative for one-time extras: pay the extra, then keep the total
    # term and recompute a lower installment for the rest of the schedule.
    # Phase 1 runs the first periods at the full installment (extra applied);
    # phase 2 amortizes the remaining balance over the remaining periods.
    def reduce_installment_alternative(_reduce_term_result)
      return nil unless @kind == "one_time_extra"

      first_number = start_installment_number
      split = extra_split_point.to_i
      term = baseline_installments
      return nil if split < 1 || split >= term

      phase1 = Credits::Amortization::ScheduleBuilder.build(
        **schedule_options(balance, base_installment), extras: extras, cap: split
      )
      balance_after_extra = phase1.final_balance
      return nil if balance_after_extra <= 0

      remaining = term - split
      new_installment = annuity_installment(balance_after_extra, remaining) + insurance + other
      phase2 = Credits::Amortization::ScheduleBuilder.build(
        **schedule_options(balance_after_extra, new_installment).merge(
          start_installment_number: first_number + split,
          first_payment_date: Credits::Amortization::Period.advance(phase1.rows.last.date, frequency)
        ),
        cap: remaining
      )

      {
        "new_installment_amount" => money(new_installment),
        "reduction" => money(base_installment - new_installment),
        "installments" => phase1.installments + phase2.installments,
        "installments_eliminated" => 0,
        "payoff_date" => phase2.payoff_date&.iso8601,
        "future_interest" => money(phase1.future_interest + phase2.future_interest),
        "interest_saved" => money(baseline_interest - (phase1.future_interest + phase2.future_interest)),
        "extra_cash" => money(phase1.extra_cash)
      }
    end

    def extra_split_point
      (@params["after_period"] || 1).to_i
    end

    def required_extra_for(target_installments)
      target = [target_installments, 1].max
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
      # Rounding must never finish later than the requested target.
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

    def extras
      case @kind
      when "one_time_extra"
        { one_time: { after_period: (@params["after_period"] || 1).to_i, amount: amount } }
      else
        recurring_extras(amount)
      end
    end

    def recurring_extras(value)
      { recurring: {
        start_period: (@params["start_period"] || 1).to_i,
        every_n_periods: (@params["every_n_periods"] || 1).to_i,
        amount: value
      } }
    end

    def amount
      BigDecimal(MoneyFormat.normalize(@params["amount"]).to_s)
    rescue ArgumentError, TypeError
      0.to_d
    end

    def target_earlier
      @params["months_earlier"].present? ? @params["months_earlier"].to_i : nil
    end

    def baseline_installments
      @projection.future_rows.size
    end

    def baseline_interest
      @baseline_interest ||= @projection.future_rows.sum { |row| row["interest"].to_d }
    end

    def balance
      @balance ||= first_future_row["opening_balance"].to_d
    end

    def first_future_row
      @first_future_row ||= @projection.future_rows.first || raise(ArgumentError, "projection has no future rows")
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

    # Classic annuity: balance × i / (1 − (1 + i)^−N), computed in float and
    # rounded to cents — the amortization engine itself stays BigDecimal.
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
