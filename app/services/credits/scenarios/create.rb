# frozen_string_literal: true

module Credits
  module Scenarios
    # Create
    # Persists a simulation scenario (max 3 per credit) computing its results
    # through Credits::Simulator against the stored projection. The kind is
    # the application type of the extraordinary payment.
    #
    # Methods: call
    #
    # Example:
    #   Credits::Scenarios::Create.call(money_source: loan, kind: "reduce_term",
    #                                   name: "+500 mil", params: { "amount" => "500000" })
    class Create
      DEFAULT_NAMES = {
        "reduce_term" => lambda { |params|
          "+#{MoneyFormat.currency(BigDecimal(MoneyFormat.normalize(params['amount'])))} para terminar antes"
        },
        "reduce_installment" => lambda { |params|
          "+#{MoneyFormat.currency(BigDecimal(MoneyFormat.normalize(params['amount'])))} para pagar menos cada mes"
        },
        "prepay_installments" => lambda { |params|
          "+#{MoneyFormat.currency(BigDecimal(MoneyFormat.normalize(params['amount'])))} adelantando cuotas"
        },
        "target_payoff" => lambda { |params|
          "Terminar #{params['months_earlier'].to_i} cuotas antes"
        }
      }.freeze

      ALLOWED_INPUT_KINDS = Credits::Simulator::STRATEGIES + Credits::Simulator::LEGACY_STRATEGIES.keys

      def self.call(money_source:, kind:, name: nil, params: {})
        new(money_source, kind, name, params).call
      end

      def initialize(money_source, kind, name, params)
        @money_source = money_source
        @kind = kind
        @name = name
        @params = (params || {}).stringify_keys
      end

      def call
        projection = @money_source.credit_projection
        return ServiceResult.error([ I18n.t("credits.scenarios.missing_projection", default: "Primero genera la proyección del crédito.") ]) if projection.nil?
        unless ALLOWED_INPUT_KINDS.include?(@kind)
          return ServiceResult.error([ I18n.t("credits.scenarios.invalid_kind", default: "Tipo de escenario inválido.") ])
        end

        scenario = @money_source.credit_scenarios.build(
          name: default_name, kind: @kind, params: normalized_params,
          results: Credits::Simulator.run(projection: projection, strategy: @kind, params: normalized_params),
          computed_at: Time.current
        )
        scenario.save!
        ServiceResult.success(scenario)
      rescue ActiveRecord::RecordInvalid => e
        ServiceResult.error(e.record.errors.full_messages)
      end

      private

      def default_name
        @name.presence || DEFAULT_NAMES.fetch(@kind, ->(_p) { @kind.to_s.humanize }).call(@params)
      end

      def normalized_params
        normalized = @params.slice("after_period", "every_n_periods", "start_period", "repeat_every", "months_earlier")
                            .transform_values(&:to_i)
        normalized["repeat_every"] = normalized.delete("every_n_periods") if normalized["every_n_periods"]
        normalized["after_period"] = normalized.delete("start_period") if normalized["start_period"]
        normalized["amount"] = MoneyFormat.normalize(@params["amount"]).to_s if @params["amount"].present?
        normalized
      end
    end
  end
end
