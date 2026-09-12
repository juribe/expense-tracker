# frozen_string_literal: true

module ExpensePlayground
  module Evaluations
    # Aggregates an evaluation run's case results into a compact hash stored
    # in evaluation_runs.metrics. All values are plain JSON-safe scalars.
    #
    #   Metrics.for(run)
    #   # => {
    #   #   "total_cases" => 3, "passed" => 2, "failed" => 0, "errored" => 1,
    #   #   "accuracy" => 0.6667, "json_valid" => 2,
    #   #   "fields" => { "amount" => { "compared" => 3, "passed" => 3 }, ... },
    #   #   "tokens" => { "input" => 1200, "output" => 340 },
    #   #   "cost" => 0.0,
    #   #   "errors" => [...]
    #   # }
    #
    # Metrics reads persisted case rows, so it is safe to call repeatedly and
    # can be re-applied when cases are re-run (idempotent).
    module Metrics
      TERMINAL = %w[passed failed error].freeze

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
        cost = resolved.sum { |c| c.cost.to_f }

        payload = {
          "total_cases" => total,
          "passed" => passed,
          "failed" => failed,
          "errored" => errored,
          "pending" => [ total - passed - failed - errored, 0 ].max,
          "accuracy" => accuracy(passed, total),
          "json_valid" => resolved.where(json_valid: true).count,
          "fields" => field_aggregates(resolved),
          "tokens" => tokens,
          "cost" => cost.round(8),
          "errors" => error_messages(resolved)
        }
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