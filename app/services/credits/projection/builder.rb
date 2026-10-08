# frozen_string_literal: true

module Credits
  module Projection
    # Builder
    # Compiles and persists the credit projection: collects the inputs,
    # builds the future amortization schedule, replays the original schedule
    # (when original terms are known) to compare projected vs actual
    # payments, and stores the result as jsonb on a single row per money
    # source. When an existing projection is fresh (same fingerprint) it is
    # returned untouched; staleness or missing data triggers rebuild.
    #
    # Methods: call
    #
    # Example:
    #   Builder.call(money_source: loan)                       # => ServiceResult
    #   Builder.call(money_source: loan, overrides: {...})     # reconstruction
    class Builder
      CRITICAL_KEYS = {
        "balance" => "saldo pendiente",
        "interest_rate" => "tasa de interés",
        "installment_amount" => "valor de la cuota"
      }.freeze
      RATE_TYPE_LABELS = { "effective_annual" => "EA", "nominal_annual" => "NA", "monthly" => "mensual" }.freeze
      FREQUENCY_LABELS = { "weekly" => "semana", "biweekly" => "quincena", "monthly" => "mes", "quarterly" => "trimestre" }.freeze
      DEVIATION_THRESHOLD = 0.10

      def self.call(money_source:, overrides: {}, force: false)
        existing = money_source.credit_projection
        return ServiceResult.success(existing) if !force && existing && !existing.stale?

        new(money_source, overrides).call
      end

      def initialize(money_source, overrides)
        @money_source = money_source
        @overrides = overrides || {}
        @inputs = Credits::DataCollector.call(money_source: money_source, overrides: overrides)
                      .each_with_object({}) { |(key, value), hash| hash[key.to_s] = value }
      end

      def call
        errors = missing_critical_errors
        return ServiceResult.error(errors) if errors.any?

        projection = find_or_build_projection
        persist_projection(projection)
        refresh_scenarios!(projection)
        ServiceResult.success(projection)
      end

      private

      def missing_critical_errors
        CRITICAL_KEYS.filter_map do |key, label|
          "Falta el #{label} del crédito para calcular la proyección." if @inputs[key].blank?
        end
      end

      def find_or_build_projection
        @money_source.credit_projection || @money_source.build_credit_projection
      end

      def persist_projection(projection)
        projection.assign_attributes(
          inputs: marshalled_inputs,
          schedule: schedule_json,
          summary: summary_json,
          assumptions: assumptions,
          estimated: estimated?,
          fingerprint: current_fingerprint,
          computed_at: Time.current
        )
        projection.save!
      end

      def marshalled_inputs
        @inputs.merge(
          "periodic_rate" => periodic_rate.to_s("F"),
          "next_payment_date" => next_payment_date.iso8601,
          "start_installment_number" => first_projected_number,
          "engine" => "fixed_installment"
        ).transform_values do |value|
          case value
          when BigDecimal then money(value)
          when Date then value.iso8601
          when ActiveSupport::TimeWithZone, Time then value.iso8601
          else value
          end
        end
      end

      def schedule_json
        { "future" => projection_result.rows.map { |row| row_attributes(row) },
          "past" => past_rows_json }
      end

      def row_attributes(row)
        {
          "installment_number" => row.installment_number,
          "date" => row.date.iso8601,
          "opening_balance" => money(row.opening_balance),
          "principal" => money(row.principal),
          "interest" => money(row.interest),
          "insurance" => money(row.insurance),
          "other" => money(row.other),
          "total_payment" => money(row.total_payment),
          "closing_balance" => money(row.closing_balance)
        }
      end

      def past_rows_json
        payments.each_with_index.map do |payment, index|
          number = number_for(index)
          projected = replay_rows_by_number[number]
          row = {
            "installment_number" => number,
            "date" => payment.date.iso8601,
            "principal" => money(payment.principal_amount),
            "interest" => money(payment.interest_amount),
            "insurance" => money(payment.insurance_amount),
            "other" => money(payment.other_amount),
            "total_payment" => money(payment.amount),
            "closing_balance" => nil
          }
          next row unless projected

          row["projected_interest"] = money(projected.interest)
          row["projected_principal"] = money(projected.principal)
          row["deviates"] = deviations.any? { |deviation| deviation["installment_number"] == number }
          row
        end
      end

      def periodic_rate
        @_periodic_rate ||= Credits::Rate::PeriodConverter.call(
          rate: @inputs["interest_rate"], rate_type: @inputs["interest_rate_type"],
          frequency: @inputs["payment_frequency"]
        )
      end

      def projection_result
        @projection_result ||= Credits::Amortization::ScheduleBuilder.build(
          balance: @inputs["balance"],
          periodic_rate: periodic_rate,
          installment_amount: @inputs["installment_amount"],
          insurance: recurring_insurance,
          other: recurring_other,
          start_installment_number: first_projected_number,
          first_payment_date: next_payment_date,
          frequency: @inputs["payment_frequency"]
        )
      end

      def first_projected_number
        (@inputs["current_installment_number"] || 0).to_i + 1
      end

      def recurring_insurance
        user_or_latest("insurance_amount", "latest_insurance")
      end

      def recurring_other
        user_or_latest("other_amount", "latest_other")
      end

      def user_or_latest(override_key, input_key)
        @inputs[input_key].to_d
      end

      def next_payment_date
        @next_payment_date ||= begin
          anchor = anchor_date
          frequency = @inputs["payment_frequency"]
          anchor = Credits::Amortization::Period.advance(anchor, frequency) while anchor <= Date.current
          anchor
        end
      end

      def anchor_date
        if @inputs["latest_payment_date"].present?
          Credits::Amortization::Period.advance(@inputs["latest_payment_date"], @inputs["payment_frequency"])
        elsif @inputs["start_date"].present?
          periods = @inputs["current_installment_number"].to_i
          date = @inputs["start_date"]
          periods.times { date = Credits::Amortization::Period.advance(date, @inputs["payment_frequency"]) }
          date
        else
          Date.current
        end
      end

      def summary_json
        result = projection_result
        rows = result.rows
        {
          "outstanding_balance" => money(@inputs["balance"]),
          "current_installment_number" => @inputs["current_installment_number"],
          "installment_amount" => money(@inputs["installment_amount"]),
          "next_payment_date" => next_payment_date.iso8601,
          "remaining_installments" => rows.size,
          "payoff_date" => result.payoff_date&.iso8601,
          "actual_payments_count" => @inputs["actual_payments_count"],
          "past_principal" => money(actual_sums[:principal]),
          "past_interest" => money(actual_sums[:interest]),
          "past_insurance" => money(actual_sums[:insurance]),
          "past_other" => money(actual_sums[:other]),
          "future_principal" => money(result.future_principal),
          "future_interest" => money(result.future_interest),
          "future_insurance" => money(result.future_insurance),
          "future_other" => money(result.future_other),
          "total_remaining" => money(result.future_total),
          "schedule_truncated" => result.truncated?,
          "needs_review" => deviations.any?,
          "deviations" => deviations
        }
      end

      def actual_sums
        @_actual_sums ||= payments.each_with_object({ principal: 0.to_d, interest: 0.to_d,
                                                     insurance: 0.to_d, other: 0.to_d }) do |payment, sums|
          sums[:principal] += payment.principal_amount.to_d
          sums[:interest] += payment.interest_amount.to_d
          sums[:insurance] += payment.insurance_amount.to_d
          sums[:other] += payment.other_amount.to_d
        end
      end

      def payments
        @payments ||= @money_source.payments.order(:date, :id)
      end

      # Compares recorded payments against a replay of the original schedule
      # (only possible when the original principal, term and start date are
      # known). The installment number of each payment is derived from the
      # credit's installments_paid counter.
      def replay_rows_by_number
        @_replay_rows_by_number ||= begin
          credit_account = @money_source.credit_account
          if credit_account&.principal_amount.present? && credit_account&.installment_count.present? &&
             @inputs["start_date"].present?
            replay = Credits::Amortization::ScheduleBuilder.build(
              balance: credit_account.principal_amount,
              periodic_rate: periodic_rate,
              installment_amount: @inputs["installment_amount"],
              insurance: 0.to_d,
              other: 0.to_d,
              start_installment_number: 1,
              first_payment_date: @inputs["start_date"],
              frequency: @inputs["payment_frequency"]
            )
            replay.rows.index_by(&:installment_number)
          else
            {}
          end
        end
      end

      def deviations
        @deviations ||= payments.each_with_index.filter_map do |payment, index|
          number = number_for(index)
          projected = replay_rows_by_number[number]
          next if projected.nil?

          [[:interest_amount, "interest", projected.interest],
           [:principal_amount, "principal", projected.principal],
           [:insurance_amount, "insurance", projected.insurance]].filter_map do |attribute, field, expected|
            deviation_for(payment, attribute, field, expected, number)
          end
        end.flatten
      end

      def number_for(index)
        final_number = (@inputs["current_installment_number"] || payments.size).to_i
        final_number - (payments.size - 1 - index)
      end

      def deviation_for(payment, attribute, field, expected, number)
        actual = payment.public_send(attribute).to_d
        relative = expected.zero? ? (actual.positive? ? Float::INFINITY : 0) : (actual - expected).abs / expected
        return if relative <= DEVIATION_THRESHOLD

        {
          "installment_number" => number,
          "field" => field,
          "projected" => money(expected),
          "actual" => money(actual),
          "deviation" => relative == Float::INFINITY ? nil : (relative * 100).round(1)
        }
      end

      def assumptions
        list = []
        list << "Tasa de interés fija de #{rate_display} mantenida constante."
        list << "Cuota fija de #{amount_display(@inputs['installment_amount'])} mantenida constante."
        list << if recurring_insurance.positive?
                  "Seguro constante de #{amount_display(recurring_insurance)} por cuota."
                else
                  "Sin seguro registrado; se asume $0 en cuotas futuras."
                end
        list << "Interés calculado con la tasa periódica #{periodic_rate_percent}% por #{frequency_label}."
        list << if @inputs["actual_payments_count"].positive?
                  "Proyección basada en #{@inputs['actual_payments_count']} pagos reales registrados."
                else
                  "Proyección estimada: los valores reales pueden diferir por interés diario, " \
                    "redondeos o pagos extraordinarios previos."
                end
        list << "Cuota supuesta constante desde el desembolso para comparar lo proyectado con lo real." if replay_available?
        list << "El cronograma se truncó al límite de cuotas; revisar los datos del crédito." if projection_result.truncated?
        list
      end

      def estimated?
        @inputs["user_supplied"].any? || @inputs["actual_payments_count"].zero?
      end

      def current_fingerprint
        CreditProjection.current_fingerprint_parts(@money_source).join(":")
      end

      def refresh_scenarios!(projection)
        @money_source.credit_scenarios.find_each do |scenario|
          results = Credits::Simulator.run(projection: projection, kind: scenario.kind, params: scenario.params)
          scenario.update!(results: results, computed_at: Time.current)
        end
      end

      def rate_display
        "#{@inputs['interest_rate']}% #{RATE_TYPE_LABELS.fetch(@inputs['interest_rate_type'], '')}".strip
      end

      def periodic_rate_percent
        (periodic_rate * 100).round(6).to_s("F")
      end

      def frequency_label
        FREQUENCY_LABELS.fetch(@inputs["payment_frequency"], @inputs["payment_frequency"])
      end

      def amount_display(value)
        MoneyFormat.number(value.to_d)
      end

      def money(value)
        value.to_d.round(2).to_s("F")
      rescue NoMethodError, TypeError
        "0.0"
      end

      def replay_available?
        replay_rows_by_number.any?
      end
    end
  end
end
