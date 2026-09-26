# frozen_string_literal: true

module Ai
  # Persists one AiRequest row per routed resolution step (cache hit,
  # deterministic win, cheap/strong attempt) so AI usage, fallback rate and
  # cache-hit rate stay observable from plain SQL. Recording failures never
  # break the business flow.
  module Recorder
    module_function

    # When a block is given it is executed and its runtime recorded as
    # latency_ms; the block's return value is passed through unchanged.
    def record(task:, user: nil, strategy:, provider: nil, status: "ok",
               confidence: nil, escalated: false, error: nil,
               input_tokens: nil, output_tokens: nil, latency_ms: nil,
               prompt: nil, output: nil)
      result = nil
      if block_given?
        started = monotonic
        result = yield
        latency_ms = ((monotonic - started) * 1000).round
      end

      write(
        task: task, user: user, strategy: strategy, provider: provider,
        status: status, confidence: confidence, escalated: escalated,
        error: error, input_tokens: input_tokens, output_tokens: output_tokens,
        latency_ms: latency_ms, prompt: prompt, output: output
      )
      result
    end

    def write(task:, user:, strategy:, provider:, status:, confidence:, escalated:,
              error:, input_tokens:, output_tokens:, latency_ms:,
              prompt: nil, output: nil)
      AiRequest.create!(
        user: user,
        task: task.to_s,
        strategy: strategy.to_s,
        provider: provider&.name,
        model: provider&.model,
        status: status,
        confidence: confidence,
        escalated: escalated,
        error: error,
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        latency_ms: latency_ms,
        prompt: truncate_prompt(prompt),
        output: output&.to_s&.truncate(20_000)
      )
    rescue StandardError => e
      Rails.logger.warn("[Ai::Recorder] failed to record AI usage: #{e.class}: #{e.message}")
      nil
    end

    # Keep observability rows bounded: each message content is truncated, and
    # no raw image/multimodal payload is ever stored here.
    def truncate_prompt(messages)
      return nil if messages.nil?

      messages.map do |message|
        { role: message[:role], content: message[:content].to_s.truncate(10_000) }
      end
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
