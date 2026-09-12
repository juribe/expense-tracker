# frozen_string_literal: true

module ExpensePlayground
  module Evaluations
    # Runs ONE dataset row through the FULL existing Expense Playground
    # pipeline. This is the heart of the evaluation: the only variable is the
    # provider/model carried by the run, which temporarily overrides the AI
    # configuration used downstream (no separate/direct-LLM path is involved).
    #
    # The status written back to the case row is one of:
    #   passed  the pipeline produced a valid result and every required field
    #           present in expected_json matched
    #   failed  a result was produced but at least one field did not match
    #   error   the pipeline could not produce any result (extraction failed)
    class CaseProcessor
      def self.call(run:, evaluation_case:)
        new(run: run, evaluation_case: evaluation_case).call
      end

      def initialize(run:, evaluation_case:)
        @run = run
        @case_record = evaluation_case
      end

      def call
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        execution = Ai::Execution.new(provider: @run.provider, model: @run.model, force_ai: true)
        input = ExpensePlayground::Input.new(type: "text", text: @case_record.message)

        processing = ExpensePlayground::ProcessingService.call(
          user: @run.user,
          input: input,
          execution: execution
        )
        latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

        persist(processing, latency_ms)
      end

      private

      def persist(processing, latency_ms)
        if processing.ok?
          build_result(processing, latency_ms)
        else
          message = processing.errors.join(" ").presence || "The pipeline could not produce an expense."
          @case_record.update!(status: "error", error: message, latency_ms: latency_ms, actual_json: nil)
          :error
        end
      end

      def build_result(processing, latency_ms)
        built = ResultBuilder.call(candidate: processing.candidate)
        comparison = Comparator.call(expected: @case_record.expected_json, actual: built[:json])

        @case_record.update!(
          actual_json: built[:json],
          json_valid: built[:valid],
          field_results: comparison[:fields].map do |field, result|
            { field: field.to_s, compared: result[:compared], matched: result[:matched] }
          end,
          status: comparison[:full_match] ? "passed" : "failed",
          latency_ms: latency_ms,
          error: nil
        )
        comparison[:full_match] ? :passed : :failed
      end
    end
  end
end