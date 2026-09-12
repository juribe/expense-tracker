# frozen_string_literal: true

module ExpensePlayground
  module Evaluations
    # Aggregates an evaluation run's case results into a compact hash stored
    # in evaluation_runs.metrics. All values are plain JSON-safe scalars.
    #
    #   Metrics.for(run)
    #   # => {
    #   #   "total_cases" => 3, "passed_cases" => 2, "failed_cases" => 0, "errored" => 1,
    #   #   "overall_accuracy" => 0.6667, "full_record_accuracy" => 0.6667,
    #   #   "json_validity" => 0.6667, "average_latency" => 120.0,
    #   #   "total_input_tokens" => 1200, "total_output_tokens" => 340,
    #   #   "input_cost" => 0.0, "output_cost" => 0.0, "cost" => 0.0,
    #   #   "fields" => { "amount" => { "compared" => 3, "passed" => 3 }, ... },
    #   #   "field_accuracy" => { "amount" => 1.0, "date" => nil, ... },
    #   #   "amount_accuracy" => 1.0, "date_accuracy" => nil, ...,
    #   #   "errors" => [...]
    #   # }
    #
    # Metrics reads persisted case rows, so it is safe to call repeatedly and
    # can be re-applied when cases are re-run (idempotent).
    module Metrics
      TERMINAL = %w[passed failed error].freeze
      FIELDS = %w[intent amount date activity category subcategory money_source currency].freeze

      module_function

      def for(run, error: nil)
        cases = run.evaluation_cases
        total = run.total_cases.to_i
        passed = cases.where(status: "passed").count
        failed = cases.where(status: "failed").count
        errored = cases.where(status: "error").count

        resolved = cases.where(status: TERMINAL)
        tokens = {
          "input" => resolved.sum(:input_tokens).to_i,
          "output" => resolved.sum(:output_tokens).to_i
        }
        input_cost = resolved.sum(:input_cost).to_f
        output_cost = resolved.sum(:output_cost).to_f
        total_cost = (input_cost + output_cost).round(8)
        accuracy = accuracy(passed, total)
        json_valid = resolved.where(json_valid: true).count
        field_aggregates = field_aggregates(resolved)

        payload = {
          "total_cases" => total,
          "passed_cases" => passed,
          "failed_cases" => failed,
          "errored" => errored,
          "pending" => [ total - passed - failed - errored, 0 ].max,
          "overall_accuracy" => accuracy,
          "accuracy" => accuracy,
          "full_record_accuracy" => accuracy,
          "json_valid" => json_valid,
          "json_validity" => ratio(json_valid, total),
          "average_latency" => average_latency(resolved),
          "tokens" => tokens,
          "total_input_tokens" => tokens["input"],
          "total_output_tokens" => tokens["output"],
          "input_cost" => input_cost.round(8),
          "output_cost" => output_cost.round(8),
          "cost" => total_cost,
          "total_cost" => total_cost,
          "fields" => field_aggregates,
          "errors" => error_messages(resolved)
        }
        payload["field_accuracy"] = field_accuracy(field_aggregates)
        payload.merge!(flat_field_accuracy(payload["field_accuracy"]))
        payload["error"] = error if error.present?
        payload
      end

      # Reads a dotted metric key, e.g. "fields.amount.passed" or "accuracy".
      def metric(metrics, key)
        node = metrics
        key.to_s.split(".").each do |part|
          return nil unless node.is_a?(Hash)

          node = node[part] || node[part.to_sym]
        end
        node
      end

      def accuracy(passed, total)
        return 0.0 if total.zero?

        (passed.to_f / total).round(4)
      end

      def ratio(value, total)
        return 0.0 if total.zero?

        (value.to_f / total).round(4)
      end

      def field_accuracy(aggregates)
        FIELDS.to_h do |field|
          [ field, field_ratio(aggregates[field]) ]
        end
      end

      def flat_field_accuracy(accuracy_map)
        accuracy_map.to_h { |field, value| [ "#{field}_accuracy", value ] }
      end

      def field_ratio(aggregate)
        return nil if aggregate.nil? || aggregate["compared"].to_i.zero?

        (aggregate["passed"].to_f / aggregate["compared"]).round(4)
      end

      def average_latency(rows)
        latencies = rows.pluck(:latency_ms).compact.select(&:positive?)
        return 0.0 if latencies.empty?

        (latencies.sum.to_f / latencies.size).round(1)
      end

      def field_aggregates(rows)
        aggregates = Hash.new { |hash, field| hash[field] = { "compared" => 0, "passed" => 0 } }
        rows.each do |case_record|
          Array(case_record.field_results).each do |result|
            next unless result.is_a?(Hash)

            field = field_name(result)
            next if field.blank?

            next unless result["compared"]

            aggregates[field]["compared"] += 1
            aggregates[field]["passed"] += 1 if result["matched"]
          end
        end
        aggregates.sort_by { |field, _| field }.to_h
      end

      def field_name(result)
        result["field"] || result[:field].to_s
      end

      def error_messages(rows)
        rows.where.not(error: nil).pluck(:error).reject(&:blank?).uniq.first(20)
      end
    end
  end
end
