# frozen_string_literal: true

require "test_helper"

module Ai
  class RouterTest < ActiveSupport::TestCase
    # Minimal task double driven purely by provider responses.
    class FakeTask < Ai::Tasks::Base
      def initialize(cache_entry: nil)
        @cache_entry = cache_entry
      end

      def cache_lookup(_input, _context)
        @cache_entry
      end

      def messages(input, _context)
        [ { role: "user", content: input.to_s } ]
      end

      def parse(content, _input, _context)
        payload = parse_json(content)
        raise InvalidResponse, "invalid" unless payload.is_a?(Hash) && payload["value"]

        { data: payload["value"], confidence: payload["confidence"] }
      end
    end

    setup do
      @user = User.create!(name: "Router User", email: "router@example.com", password: "password123")
    end

    def with_providers(cheap:, strong:)
      stub_method(Ai::Providers, :cheap, ->(*) { cheap }) do
        stub_method(Ai::Providers, :strong, ->(*) { strong }) do
          yield
        end
      end
    end

    def ok_response(value:, confidence: 0.95, tokens: true)
      { content: { value: value, confidence: confidence }.to_json,
        input_tokens: tokens ? 10 : 0, output_tokens: tokens ? 5 : 0 }
    end

    test "cache hit avoids every provider call" do
      strong = FakeAiProvider.new(responses: [])
      task = FakeTask.new(cache_entry: { data: "cached", confidence: 1.0 })

      with_providers(cheap: nil, strong: strong) do
        result = Ai::Router.call(task: task, input: "anything", context: { user: @user })

        assert result.ok?
        assert_equal "cached", result.data
        assert_equal "cache", result.strategy
        assert_equal 0, strong.calls.count
      end

      row = AiRequest.last
      assert_equal "cache", row.strategy
      assert_equal "ok", row.status
      assert_equal @user.id, row.user_id
    end

    test "confident cheap result is accepted and the strong model is never called" do
      cheap = FakeAiProvider.new(responses: [ ok_response(value: "cheap") ])
      strong = FakeAiProvider.new(responses: [])

      with_providers(cheap: cheap, strong: strong) do
        result = Ai::Router.call(task: FakeTask.new, input: "msg")

        assert result.ok?
        assert_equal "cheap", result.data
        assert_equal "cheap_ai", result.strategy
        assert_equal 1, cheap.calls.count
        assert_equal 0, strong.calls.count
      end

      row = AiRequest.where(strategy: "cheap_ai").last
      assert_equal "ok", row.status
      assert_equal 10, row.input_tokens
      assert_equal 5, row.output_tokens
      refute row.escalated
    end

    test "low-confidence cheap result escalates to the strong model" do
      cheap = FakeAiProvider.new(responses: [ ok_response(value: "shaky", confidence: 0.61) ])
      strong = FakeAiProvider.new(responses: [ ok_response(value: "solid", confidence: 0.99) ])

      with_providers(cheap: cheap, strong: strong) do
        result = with_env({ "AI_CHEAP_CONFIDENCE_THRESHOLD" => "0.90" }) do
          Ai::Router.call(task: FakeTask.new, input: "msg")
        end

        assert result.ok?
        assert_equal "solid", result.data
        assert_equal "strong_ai", result.strategy
        assert_equal 1, cheap.calls.count
        assert_equal 1, strong.calls.count
      end

      cheap_row = AiRequest.where(strategy: "cheap_ai").last
      assert_equal "low_confidence", cheap_row.status
      assert_in_delta 0.61, cheap_row.confidence, 0.001

      strong_row = AiRequest.where(strategy: "strong_ai").last
      assert_equal "ok", strong_row.status
      assert strong_row.escalated
    end

    test "invalid cheap output escalates to the strong model" do
      cheap = FakeAiProvider.new(responses: [ "not json at all" ])
      strong = FakeAiProvider.new(responses: [ ok_response(value: "solid") ])

      with_providers(cheap: cheap, strong: strong) do
        result = Ai::Router.call(task: FakeTask.new, input: "msg")

        assert result.ok?
        assert_equal "strong_ai", result.strategy
      end

      assert_equal "error", AiRequest.where(strategy: "cheap_ai").last.status
    end

    test "cheap provider failure falls back to the strong model" do
      cheap = FakeAiProvider.new(responses: [ Ai::Provider::Error.new("timeout") ])
      strong = FakeAiProvider.new(responses: [ ok_response(value: "solid") ])

      with_providers(cheap: cheap, strong: strong) do
        result = Ai::Router.call(task: FakeTask.new, input: "msg")

        assert result.ok?
        assert_equal "strong_ai", result.strategy
      end

      assert_equal "error", AiRequest.where(strategy: "cheap_ai").last.status
      assert_match(/timeout/, AiRequest.where(strategy: "cheap_ai").last.error)
    end

    test "skips the cheap tier entirely when it is not configured" do
      strong = FakeAiProvider.new(responses: [ ok_response(value: "solid") ])

      with_providers(cheap: nil, strong: strong) do
        result = Ai::Router.call(task: FakeTask.new, input: "msg")

        assert result.ok?
        assert_equal "strong_ai", result.strategy
        assert_equal 1, strong.calls.count
      end
    end

    test "when every tier fails the caller gets a recoverable error" do
      strong = FakeAiProvider.new(responses: [ Ai::Provider::Error.new("AI HTTP 500") ])

      with_providers(cheap: nil, strong: strong) do
        result = Ai::Router.call(task: FakeTask.new, input: "msg")

        refute result.ok?
        assert result.needs_clarification?
        assert_match(/AI HTTP 500/, result.error)
      end
    end

    test "fails cleanly when no provider is configured at all" do
      with_providers(cheap: nil, strong: nil) do
        result = Ai::Router.call(task: FakeTask.new, input: "msg")

        refute result.ok?
        assert_equal "AI is not configured", result.error
      end
    end

    test "the confidence threshold is configurable" do
      cheap = FakeAiProvider.new(responses: [ ok_response(value: "cheap", confidence: 0.7) ])
      strong = FakeAiProvider.new(responses: [])

      with_providers(cheap: cheap, strong: strong) do
        result = with_env({ "AI_CHEAP_CONFIDENCE_THRESHOLD" => "0.60" }) do
          Ai::Router.call(task: FakeTask.new, input: "msg")
        end

        assert result.ok?
        assert_equal "cheap_ai", result.strategy
        assert_equal 0, strong.calls.count
      end
    end

    test "raises for unknown task names" do
      assert_raises(ArgumentError) { Ai::Router.call(task: :nope, input: "x") }
    end
  end
end
