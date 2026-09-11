# frozen_string_literal: true

require "test_helper"

module Ai
  class ProviderTest < ActiveSupport::TestCase
    FakeResponse = Struct.new(:code, :body)

    class FakeHttp
      attr_reader :request_count

      def initialize(responses)
        @responses = responses
        @request_count = 0
      end

      def request(_request)
        @request_count += 1
        response = @responses.shift
        raise "no stubbed response left" unless response

        response
      end
    end

    def provider
      Ai::Provider.new(name: "test", model: "test-model", api_key: "key",
                       base_url: "https://example.com/v1/chat/completions")
    end

    test "chat parses content and token usage" do
      body = {
        choices: [ { message: { content: "{\"ok\":true}" } } ],
        usage: { prompt_tokens: 12, completion_tokens: 7 },
        model: "test-model"
      }.to_json
      p = provider
      p.define_singleton_method(:perform_request) { |_pair| FakeResponse.new("200", body) }

      response = p.chat(messages: [ { role: "user", content: "hi" } ])

      assert_equal "{\"ok\":true}", response.content
      assert_equal 12, response.input_tokens
      assert_equal 7, response.output_tokens
      assert_equal "test-model", response.model
    end

    test "chat raises when the content is empty" do
      body = { choices: [ { message: { content: "" } } ] }.to_json
      p = provider
      p.define_singleton_method(:perform_request) { |_pair| FakeResponse.new("200", body) }

      assert_raises(Ai::Provider::Error) { p.chat(messages: []) }
    end

    test "chat raises when the provider is not configured" do
      unconfigured = Ai::Provider.new(name: "test", model: "m", api_key: nil, base_url: nil)

      error = assert_raises(Ai::Provider::Error) { unconfigured.chat(messages: []) }
      assert_match(/not configured/, error.message)
    end

    test "chat raises on invalid JSON payloads" do
      p = provider
      p.define_singleton_method(:perform_request) { |_pair| FakeResponse.new("200", "not json") }

      assert_raises(Ai::Provider::Error) { p.chat(messages: []) }
    end

    test "retries rate-limited (429) responses with backoff" do
      p = provider
      responses = [ FakeResponse.new("429"), FakeResponse.new("429"), FakeResponse.new("200", "{}") ]
      fake_http = FakeHttp.new(responses)
      slept = []
      p.define_singleton_method(:sleep) { |seconds| slept << seconds }

      response = p.send(:perform_request, [ fake_http, nil ])

      assert_equal "200", response.code
      assert_equal [ 1, 2 ], slept
      assert_equal 3, fake_http.request_count
    end

    test "gives up after two 429 retries and reports the rate limit" do
      p = provider
      responses = [ FakeResponse.new("429"), FakeResponse.new("429"), FakeResponse.new("429") ]
      fake_http = FakeHttp.new(responses)
      p.define_singleton_method(:sleep) { |_seconds| nil }

      error = assert_raises(Ai::Provider::Error) { p.send(:perform_request, [ fake_http, nil ]) }

      assert_equal "AI HTTP 429", error.message
      assert_equal 3, fake_http.request_count
    end

    test "non-429 HTTP errors fail immediately without retries" do
      p = provider
      fake_http = FakeHttp.new([ FakeResponse.new("500") ])
      p.define_singleton_method(:sleep) { |_seconds| nil }

      error = assert_raises(Ai::Provider::Error) { p.send(:perform_request, [ fake_http, nil ]) }

      assert_equal "AI HTTP 500", error.message
      assert_equal 1, fake_http.request_count
    end

    test "a 429 caused by an exhausted budget fails fast without retries" do
      p = provider
      body = { error: { message: "Budget has been exceeded!", type: "budget_exceeded" } }.to_json
      fake_http = FakeHttp.new([ FakeResponse.new("429", body) ])
      p.define_singleton_method(:sleep) { |_seconds| nil }

      error = assert_raises(Ai::Provider::Error) { p.send(:perform_request, [ fake_http, nil ]) }

      assert_equal "AI HTTP 429", error.message
      assert_equal 1, fake_http.request_count
    end
  end
end
