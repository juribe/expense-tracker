# frozen_string_literal: true

module Credits
  # Comparison
  # Two view models over the simulation engine:
  #
  #   .call   — saved scenarios: "Cuota actual" baseline plus the saved
  #             scenarios, sorted by interest saved, with the best scenario
  #             per chosen objective (max savings, minimum payment, fastest
  #             payoff, best savings per extra peso).
  #   .quick  — transient "what should I do with this money?" comparison of
  #             the current state plus each strategy for one amount. Never
  #             persisted; only saved scenarios occupy the saved slots.
  class Comparison
    OBJECTIVES = %w[max_savings min_payment fastest_payoff balanced].freeze
    QUICK_STRATEGIES = %w[reduce_term reduce_installment prepay_installments].freeze

    QuickComparison = Struct.new(:current, :strategies, :amount, :mode, keyword_init: true)

    attr_reader :rows, :objective

    def self.call(projection:, objective: "max_savings")
      new(projection, objective).call
    end

    def self.quick(projection:, amount:, mode: "once")
      current = baseline_row_of(projection)
      installment = projection.summary["installment_amount"].to_d
      strategies = if mode == "recurring"
                     # Constant extra every period: what happens paying that
                     # amount on top of the installment, every installment.
                     results = Credits::Simulator.run(
                       projection: projection, strategy: "reduce_term",
                       params: { "amount" => amount.to_s, "repeat_every" => 1 }
                     )
                     [ common_row("reduce_term", results, projection).merge(
                       "payment" => money(installment + amount.to_d),
                       "repeat_every" => 1
                     ) ]
      else
                     QUICK_STRATEGIES.map do |strategy|
                       results = Credits::Simulator.run(projection: projection, strategy: strategy,
                                                        params: { "amount" => amount.to_s })
                       common_row(strategy, results, projection)
                     end
      end
      QuickComparison.new(current: current, strategies: strategies, amount: amount.to_d, mode: mode)
    end

    def self.baseline_row_of(projection)
      summary = projection.summary
      {
        "kind" => "baseline",
        "name" => I18n.t("credits.comparison.baseline", default: "Cuota actual"),
        "payment" => money(summary["installment_amount"]),
        "payoff_date" => summary["payoff_date"],
        "installments" => summary["remaining_installments"],
        "interest_saved" => "0.0",
        "future_interest" => money(summary["future_interest"]),
        "installments_eliminated" => 0,
        "extra_cash" => "0.0",
        "months_without_payment" => 0
      }
    end

    def initialize(projection, objective)
      @projection = projection
      @objective = OBJECTIVES.include?(objective) ? objective : "max_savings"
    end

    def call
      @rows = [ self.class.baseline_row_of(@projection) ] +
              scenario_rows.sort_by { |row| row["interest_saved"].to_d }.reverse
      self
    end

    def best
      candidates = rows.reject { |row| row["kind"] == "baseline" }
      return nil if candidates.empty?

      case @objective
      when "fastest_payoff" then candidates.min_by { |row| row["payoff_date"].to_s }
      when "min_payment" then candidates.min_by { |row| row["payment"].to_d }
      when "balanced" then candidates.max_by { |row| row["savings_per_extra_peso"].to_f }
      else candidates.max_by { |row| row["interest_saved"].to_d }
      end
    end

    private

    def scenario_rows
      @projection.money_source.credit_scenarios.order(:created_at).map do |scenario|
        row = self.class.common_row(scenario.kind, scenario.results, @projection).merge(
          "scenario_id" => scenario.id,
          "name" => scenario.name,
          "kind_label" => kind_label(scenario.kind),
          "savings_per_extra_peso" => savings_per_extra_peso(scenario.results)
        )
        # Fixture/back-compat: unknown kinds keep the simulator's strategy.
        row["payment"] = self.class.money(payment_for(scenario))
        row
      end
    end

    def self.common_row(strategy, results, projection)
      summary = projection.summary
      {
        "kind" => "scenario",
        "strategy" => strategy,
        "name" => nil,
        "payment" => money(ongoing_payment(strategy, results, summary["installment_amount"].to_d)),
        "payoff_date" => results["payoff_date"],
        "installments" => results["installments"],
        "interest_saved" => money(results["interest_saved"]),
        "future_interest" => money(results["future_interest"]),
        "installments_eliminated" => results["installments_eliminated"].to_i,
        "extra_cash" => money(results["extra_cash"]),
        "months_without_payment" => results["months_without_payment"].to_i,
        "installments_covered" => results["installments_covered"].to_i
      }
    end

    def self.ongoing_payment(strategy, results, installment)
      case strategy
      when "reduce_installment"
        results["new_installment"].present? ? results["new_installment"].to_d : installment
      when "target_payoff"
        results["new_total_payment"].present? ? results["new_total_payment"].to_d : installment
      else
        installment
      end
    end

    def self.money(value)
      value.to_d.round(2).to_s("F")
    rescue NoMethodError, TypeError
      "0.0"
    end

    def payment_for(scenario)
      payment = self.class.ongoing_payment(scenario.kind, scenario.results, base_installment)
      return payment unless scenario.kind == "reduce_term" && scenario.results["repeat_every"].to_i == 1

      amount = BigDecimal(MoneyFormat.normalize(scenario.params["amount"]).to_s)
      payment + amount
    rescue ArgumentError, TypeError
      base_installment
    end
    def savings_per_extra_peso(results)
      cash = results["extra_cash"].to_d
      return "0.0" if cash <= 0

      (results["interest_saved"].to_d / cash).round(4).to_s("F")
    end

    def base_installment
      summary["installment_amount"].to_d
    end

    def summary
      @summary ||= @projection.summary
    end

    def kind_label(kind)
      I18n.t("credits.scenarios.kinds.#{kind}", default: kind.humanize)
    end
  end
end
