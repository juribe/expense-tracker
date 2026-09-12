# frozen_string_literal: true

module ExpensePlayground
  module Evaluations
    # Runs ONE dataset row through the FULL existing Expense Playground
    # pipeline. This is the heart of the evaluation: the only variable is the
    # provider/model carried by the run, which temporarily overrides the AI
    # configuration used downstream (no separate/direct-LLM path is involved).
    #
    # The provider/model carried by the run, which temporarily overrides the AI
    # configuration used downstream (no separate/direct-LLM path is involved).
    #
    # Token usage and cost are captured from the AiRequest rows the override
    # writes during processing, so metrics can report latency, tokens and cost
    # per case and per run.
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
        started = monotonic
        requests_before = latest_override_request_id

        execution = Ai::Execution.new(provider: @run.provider, model: @run.model, force_ai: true)
        input = ExpensePlayground::Input.new(type: "text", text: @case_record.message)

        ExpensePlayground::ProcessingService.call(
          user: @run.user,
          input: input,
          execution: execution
        ).then do |processing|
          persist(
            processing,
            latency_ms: ((monotonic - started) * 1000).round,
            usage: usage_since(requests_before)
          )
        end
      end

      private

      def persist(processing, latency_ms:, usage:)
        if processing.ok?
          build_result(processing, latency_ms, usage)
        else
          message = processing.errors.join(" ").presence || "The pipeline could not produce an expense."
          @case_record.update!(
            status: "error", error: message, latency_ms: latency_ms, actual_json: nil,
            input_tokens: usage[:input_tokens], output_tokens: usage[:output_tokens],
            cost: usage[:cost], input_cost: usage[:input_cost], output_cost: usage[:output_cost]
          )
          :error
        end
      end

      def build_result(processing, latency_ms, usage)
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
          error: nil,
          input_tokens: usage[:input_tokens], output_tokens: usage[:output_tokens],
          cost: usage[:cost], input_cost: usage[:input_cost], output_cost: usage[:output_cost]
        )
        comparison[:full_match] ? :passed : :failed
      end

      def latest_override_request_id
        AiRequest.where(user_id: @run.user_id, strategy: "override").maximum(:id)
      end

      def usage_since(request_id)
        requests = AiRequest.where(user_id: @run.user_id, strategy: "override").where("id > ?", request_id.to_i)
        input_tokens = requests.sum(:input_tokens).to_i
        output_tokens = requests.sum(:output_tokens).to_i
        costs = Ai::Pricing.split_cost(
          input_tokens: input_tokens, output_tokens: output_tokens,
          provider: @run.provider, model: @run.model
        )
        {
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          input_cost: costs[:input],
          output_cost: costs[:output],
          cost: costs[:input] + costs[:output]
        }
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end