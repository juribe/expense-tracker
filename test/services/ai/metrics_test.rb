# frozen_string_literal: true

require "test_helper"

module Ai
  class MetricsTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Metrics User", email: "metrics@example.com", password: "password123")
    end

    def request!(strategy:, status: "ok", escalated: false, confidence: nil, task: "expense_extraction")
      AiRequest.create!(user: @user, task: task, strategy: strategy, status: status,
                        escalated: escalated, confidence: confidence,
                        input_tokens: 10, output_tokens: 5)
    end

    test "summarizes requests by strategy, fallback rate and cache hit rate" do
      request!(strategy: "deterministic")
      request!(strategy: "cache")
      request!(strategy: "cheap_ai")
      request!(strategy: "cheap_ai", status: "low_confidence", confidence: 0.5)
      request!(strategy: "strong_ai", escalated: true, confidence: 0.99)
      request!(strategy: "strong_ai")

      metrics = Ai::Metrics.summary(AiRequest.where(user: @user))

      assert_equal 6, metrics[:total_requests]
      assert_equal 1, metrics[:deterministic_requests]
      assert_equal 1, metrics[:cache_hits]
      assert_equal 2, metrics[:cheap_ai_requests]
      assert_equal 2, metrics[:strong_ai_requests]
      assert_equal 0.5, metrics[:ai_fallback_rate]
      assert_equal((1.0 / 6.0).round(4), metrics[:ai_cache_hit_rate])
      assert_equal 40, metrics[:input_tokens]
      assert_equal 20, metrics[:output_tokens]
      assert_equal 0, metrics[:failed_requests]
      assert metrics[:average_confidence].present?
    end

    test "rates are zero-safe when there is nothing to measure" do
      metrics = Ai::Metrics.summary(AiRequest.where(user: @user))

      assert_equal 0, metrics[:total_requests]
      assert_equal 0.0, metrics[:ai_fallback_rate]
      assert_equal 0.0, metrics[:ai_cache_hit_rate]
      assert_nil metrics[:average_confidence]
    end
  end
end
