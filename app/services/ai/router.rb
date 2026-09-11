# frozen_string_literal: true

module Ai
  # Routes an AI task through the cheapest acceptable resolution path:
  #
  #   cache / previously learned knowledge
  #     → cheap model (only when confidence meets the configured threshold)
  #       → strong model
  #         → a recoverable error the caller turns into a clarification
  #           request instead of silently creating wrong data
  #
  #   result = Ai::Router.call(task: :expense_extraction, input: message, context: { user: user })
  #   result.ok?                  # => true
  #   result.data                 # => task-specific structured payload
  #   result.confidence           # => 0.0..1.0
  #   result.strategy             # => "cache" | "cheap_ai" | "strong_ai"
  #   result.needs_clarification? # => true when every tier failed
  class Router
    Result = Struct.new(:ok?, :data, :confidence, :strategy, :error, keyword_init: true) do
      def needs_clarification?
        !ok?
      end
    end

    TASKS = {
      expense_extraction: "Ai::Tasks::ExpenseExtraction",
      category_classification: "Ai::Tasks::CategoryClassification",
      statement_extraction: "Ai::Tasks::StatementExtraction",
      transaction_extraction: "Ai::Tasks::TransactionExtraction",
      spreadsheet_mapping: "Ai::Tasks::SpreadsheetMapping"
    }.freeze

    class << self
      def call(task:, input:, context: {})
        new(task: task, input: input, context: context || {}).call
      end

      # Registers additional/custom tasks without touching business logic.
      def register_task(name, klass)
        TASKS[name.to_sym] = klass
      end
    end

    def initialize(task:, input:, context: {})
      @task = resolve_task(task)
      @task_name = task.is_a?(Symbol) || task.is_a?(String) ? task.to_sym : task.class.name.demodulize.underscore.to_sym
      @input = input
      @context = context
      @user = context[:user]
    end

    def call
      cached = @task.cache_lookup(@input, @context)
      if cached
        record(strategy: "cache", confidence: cached[:confidence])
        return Result.new(ok?: true, data: cached[:data], confidence: cached[:confidence],
                          strategy: "cache", error: nil)
      end

      run_tiers
    end

    private

    def resolve_task(task)
      return task if task.is_a?(Tasks::Base)

      klass = TASKS[task.to_sym]
      raise ArgumentError, "unknown AI task: #{task}" if klass.nil?

      (klass.is_a?(Class) ? klass : klass.to_s.constantize).new
    end

    def run_tiers
      escalated = false
      last_error = "AI is not configured"

      @task.tiers.each do |tier|
        provider = Providers.for(tier)
        next unless provider&.configured?

        accepted, error = attempt(tier, provider, escalated)
        return accepted if accepted

        escalated = true
        last_error = error || last_error
      end

      Result.new(ok?: false, data: nil, confidence: nil, strategy: nil, error: last_error)
    end

    # Returns [Result, nil] on acceptance or [nil, nil] when the cheap tier is
    # rejected for low confidence and [nil, message] on provider failures.
    def attempt(tier, provider, escalated)
      started = monotonic
      response = provider.chat(messages: @task.messages(@input, @context),
                               timeout: @task.timeout)
      latency_ms = ((monotonic - started) * 1000).round

      parsed = @task.parse(response.content, @input, @context)

      if tier.to_sym == Providers::TIER_CHEAP && low_confidence?(parsed[:confidence])
        record(tier, provider, status: "low_confidence", confidence: parsed[:confidence],
               latency_ms: latency_ms, usage: response, escalated: escalated)
        return [ nil, nil ]
      end

      record(tier, provider, status: "ok", confidence: parsed[:confidence],
             latency_ms: latency_ms, usage: response, escalated: escalated)
      [ Result.new(ok?: true, data: parsed[:data], confidence: parsed[:confidence],
                   strategy: "#{tier}_ai", error: nil), nil ]
    rescue Provider::Error, Tasks::Base::InvalidResponse => e
      record(tier, provider, status: "error", error: e.message,
             latency_ms: ((monotonic - started) * 1000).round, escalated: escalated)
      [ nil, e.message ]
    end

    def low_confidence?(confidence)
      return true if confidence.nil? # cheap results without confidence cannot be trusted

      confidence < @task.confidence_threshold
    end

    def record(tier = nil, provider = nil, status: "ok", confidence: nil, error: nil,
               latency_ms: nil, usage: nil, escalated: false, strategy: nil)
      Recorder.write(
        task: @task_name,
        user: @user,
        strategy: strategy || "#{tier}_ai",
        provider: provider,
        status: status,
        confidence: confidence,
        error: error,
        input_tokens: usage&.input_tokens,
        output_tokens: usage&.output_tokens,
        latency_ms: latency_ms,
        escalated: escalated
      )
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
