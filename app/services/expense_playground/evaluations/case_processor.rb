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
        # A provider/model that does not resolve to a configured vendor client
        # must fail loudly, never silently fall back to the deterministic
        # parser: the evaluation is supposed to measure the selected model.
        return fail_unusable_override unless usable_override?

        started = monotonic
        requests_before = latest_override_request_id

        execution = Ai::Execution.new(provider: @run.provider, model: @run.model, force_ai: true)
        input = ExpensePlayground::Input.new(type: "text", text: @case_record.message)

        result = ExpensePlayground::ProcessingService.call(
          user: @run.user,
          input: input,
          execution: execution
        )
        persist(
          result,
          latency_ms: ((monotonic - started) * 1000).round,
          usage: usage_since(requests_before)
        )
      end

      private

      def usable_override?
        provider = Ai::Providers.build(provider: @run.provider, model: @run.model)
        provider.present? && provider.configured?
      rescue ArgumentError
        false
      end

      def fail_unusable_override
        message = "The selected AI provider/model is not configured " \
                  "(provider=#{@run.provider}, model=#{@run.model})."
        update_case(status: "error", error: message, latency_ms: 0,
                    field_results: [], actual_json: nil,
                    usage: empty_usage)
        :error
      end

      def empty_usage
        { input_tokens: 0, output_tokens: 0, input_cost: 0.0, output_cost: 0.0, cost: 0.0 }
      end

      def persist(processing, latency_ms:, usage:)
        if usage[:failed]
          # The existing pipeline falls back to the deterministic parser when
          # the provider fails, so the message can still produce an expense.
          # An evaluation must not count that as a truthful model result: the
          # model under test failed, so the case is worth an explicit retry.
          message = usage[:error].presence || "The AI provider failed during evaluation."
          update_case(status: "error", error: message, latency_ms: latency_ms,
                      field_results: [], actual_json: nil, usage: usage)
          return :error
        end

        if processing.ok?
          build_result(processing, latency_ms, usage)
        else
          message = processing.errors.join(" ").presence || "The pipeline could not produce an expense."
          update_case(status: "error", error: message, latency_ms: latency_ms,
                      field_results: [], actual_json: nil, usage: usage)
          :error
        end
      end

      def build_result(processing, latency_ms, usage)
        built = ResultBuilder.call(candidate: processing.candidate)
        comparison = Comparator.call(expected: @case_record.expected_json, actual: built[:json])

        update_case(
          status: comparison[:full_match] ? "passed" : "failed",
          error: nil,
          latency_ms: latency_ms,
          actual_json: built[:json],
          json_valid: built[:valid],
          field_results: comparison[:fields].map do |field, result|
            { field: field.to_s, compared: result[:compared], matched: result[:matched] }
          end,
          usage: usage
        )
        comparison[:full_match] ? :passed : :failed
      end

      def update_case(status:, error:, latency_ms:, actual_json:, usage:, field_results: [], json_valid: false)
        @case_record.update!(
          status: status,
          error: error,
          latency_ms: latency_ms,
          actual_json: actual_json,
          field_results: field_results,
          json_valid: json_valid,
          input_tokens: usage[:input_tokens],
          output_tokens: usage[:output_tokens],
          cost: usage[:cost],
          input_cost: usage[:input_cost],
          output_cost: usage[:output_cost]
        )
      end

      def latest_override_request_id
        AiRequest.where(user_id: @run.user_id, strategy: "override").maximum(:id)
      end

      def usage_since(request_id)
        requests = AiRequest.where(user_id: @run.user_id, strategy: "override").where("id > ?", request_id.to_i)
        failed = requests.where(status: "error").first
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
          cost: costs[:input] + costs[:output],
          failed: failed.present?,
          error: failed&.error
        }
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
