# frozen_string_literal: true

module Ai
  # Aggregates AiRequest rows into the metrics that tell whether the
  # cheap-first architecture is actually working: how much of the traffic
  # never touches the strong model, how often the cheap tier is escalated,
  # and how much is answered from stored knowledge.
  #
  #   Ai::Metrics.summary(since: 7.days.ago)
  #   # => { cheap_ai_requests: 120, strong_ai_requests: 35, ai_fallback_rate: 0.22,
  #   #      ai_cache_hit_rate: 0.41, average_confidence: 0.93, ... }
  module Metrics
    module_function

    def summary(scope = AiRequest.all)
      {
        total_requests: scope.count,
        deterministic_requests: scope.where(strategy: "deterministic").count,
        cache_hits: scope.cache_hits.count,
        cheap_ai_requests: scope.where(strategy: "cheap_ai").count,
        strong_ai_requests: scope.where(strategy: "strong_ai").count,
        failed_requests: scope.where(status: "error").count,
        ai_fallback_rate: fallback_rate(scope),
        ai_cache_hit_rate: hit_rate(scope.cache_hits, scope),
        average_confidence: average_confidence(scope),
        input_tokens: scope.ai_calls.sum(:input_tokens),
        output_tokens: scope.ai_calls.sum(:output_tokens),
        requests_by_task: scope.group(:task).count,
        requests_by_strategy: scope.group(:strategy).count,
        requests_by_model: scope.where.not(model: nil).group(:model).count
      }
    end

    # Share of resolutions where the strong tier was only reached after the
    # cheap tier (or a preceding attempt) failed or was not confident enough.
    def fallback_rate(scope)
      cascaded = scope.where(escalated: true, strategy: "strong_ai").count
      strong_total = scope.where(strategy: "strong_ai").count
      return 0.0 if strong_total.zero?

      (cascaded.to_f / strong_total).round(4)
    end

    def hit_rate(numerator_scope, denominator_scope)
      total = denominator_scope.count
      return 0.0 if total.zero?

      (numerator_scope.count.to_f / total).round(4)
    end

    def average_confidence(scope)
      value = scope.where.not(confidence: nil).average(:confidence)
      value ? value.to_f.round(4) : nil
    end
  end
end
