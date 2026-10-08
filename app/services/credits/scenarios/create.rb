# frozen_string_literal: true

module Credits
  module Scenarios
    # Create
    # Persists a simulation scenario (max 3 per credit) computing its
    # results through Credits::Simulator against the stored projection.
    #
    # Methods: call
    #
    # Example:
    #   Credits::Scenarios::Create.call(money_source: loan, kind: "recurring_extra",
    #                                   name: "+500 mil/mes", params: { "amount" => "500000" })
    class Create
      DEFAULT_NAMES = {
        "one_time_extra" => ->(params) { "+#{MoneyFormat.currency(params['amount'].to_d)} una vez" },
        "recurring_extra" => lambda { |params|
          period = params["every_n_periods"].to_i
          base = "+#{MoneyFormat.currency(params['amount'].to_d)} por cuota"
          period > 1 ? "#{base} (cada #{period})" : base
        },
        "target_payoff" => ->(params) { "Terminar #{params['months_earlier']} cuotas antes" }
      }.freeze

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
        return ServiceResult.error(["Primero genera la proyección del crédito."]) if projection.nil?
        unless CreditScenario::KINDS.include?(@kind)
          return ServiceResult.error(["Tipo de escenario inválido."])
        end

        scenario = @money_source.credit_scenarios.build(
          name: default_name, kind: @kind, params: normalized_params,
          results: Credits::Simulator.run(projection: projection, kind: @kind, params: normalized_params),
          computed_at: Time.current
        )
        scenario.save!
        ServiceResult.success(scenario)
      rescue ActiveRecord::RecordInvalid => e
        ServiceResult.error(e.record.errors.full_messages)
      end

      private

      def default_name
        @name.presence || DEFAULT_NAMES.fetch(@kind).call(@params)
      end

      def normalized_params
        normalized = @params.slice("after_period", "every_n_periods", "start_period", "months_earlier")
                            .transform_values(&:to_i)
        normalized["amount"] = MoneyFormat.normalize(@params["amount"]).to_s if @params["amount"].present?
        normalized
      end
    end
  end
end
