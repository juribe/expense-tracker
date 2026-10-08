# frozen_string_literal: true

module Credits
  # Comparison
  # Builds the scenario table — "Cuota actual" baseline plus the saved
  # scenarios — sorted by interest saved, and picks the best scenario for
  # the chosen objective (max savings, minimum payment, fastest payoff or
  # the best balance between extra cash and savings).
  #
  # Methods: call
  #
  # Example:
  #   Comparison.call(projection: projection, objective: "max_savings")
  #     # => OpenStruct-ish { rows:, best:, objective: }
  class Comparison
    OBJECTIVES = %w[max_savings min_payment fastest_payoff balanced].freeze

    attr_reader :rows, :objective

    def self.call(projection:, objective: "max_savings")
      new(projection, objective).call
    end

    def initialize(projection, objective)
      @projection = projection
      @objective = OBJECTIVES.include?(objective) ? objective : "max_savings"
    end

    def call
      @rows = [baseline_row] + scenario_rows.sort_by { |row| row["interest_saved"].to_d }.reverse
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

    def baseline_row
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
        "savings_per_extra_peso" => "0.0"
      }
    end

    def scenario_rows
      @projection.money_source.credit_scenarios.order(:created_at).map { |scenario| scenario_row(scenario) }
    end

    def scenario_row(scenario)
      results = scenario.results
      payment = scenario_payment(scenario)
      {
        "kind" => "scenario",
        "scenario_id" => scenario.id,
        "name" => scenario.name,
        "kind_label" => kind_label(scenario.kind),
        "payment" => money(payment),
        "payoff_date" => results["payoff_date"],
        "installments" => results["installments"],
        "interest_saved" => money(results["interest_saved"]),
        "future_interest" => money(results["future_interest"]),
        "installments_eliminated" => results["installments_eliminated"].to_i,
        "extra_cash" => money(results["extra_cash"]),
        "savings_per_extra_peso" => savings_per_extra_peso(results)
      }
    end

    # The monthly payment the user carries after the scenario: recurring
    # extras raise it, one-time extras optionally reduce it.
    def scenario_payment(scenario)
      results = scenario.results
      if scenario.kind == "recurring_extra"
        amount = BigDecimal(MoneyFormat.normalize(scenario.params["amount"]).to_s)
        every = (scenario.params["every_n_periods"] || 1).to_i
        every == 1 ? base_installment + amount : base_installment
      else
        alternative = results["reduce_installment"]
        alternative.present? ? alternative["new_installment_amount"].to_d : base_installment
      end
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

    def money(value)
      value.to_d.round(2).to_s("F")
    rescue NoMethodError, TypeError
      "0.0"
    end
  end
end
