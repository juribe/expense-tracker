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

    test "chat includes max_tokens in the request body when provided" do
      captured = nil
      p = provider
      p.define_singleton_method(:perform_request) do |(http, request)|
        captured = JSON.parse(request.body)
        FakeResponse.new("200", { choices: [ { message: { content: "{}" } } ] }.to_json)
      end

      p.chat(messages: [ { role: "user", content: "hi" } ], max_tokens: 4096)

      assert_equal 4096, captured["max_tokens"]
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
      responses = [ FakeResponse.new("429"), FakeResponse.new("429"), FakeResponse.new("429"), FakeResponse.new("200", "{}") ]
      fake_http = FakeHttp.new(responses)
      slept = []
      p.define_singleton_method(:sleep) { |seconds| slept << seconds }

      response = p.send(:perform_request, [ fake_http, nil ])

      assert_equal "200", response.code
      assert_equal [ 2, 5, 10 ], slept
      assert_equal 4, fake_http.request_count
    end

    test "gives up after three 429 retries and reports the rate limit" do
      p = provider
      responses = [ FakeResponse.new("429"), FakeResponse.new("429"), FakeResponse.new("429"), FakeResponse.new("429") ]
      fake_http = FakeHttp.new(responses)
      p.define_singleton_method(:sleep) { |_seconds| nil }

      error = assert_raises(Ai::Provider::Error) { p.send(:perform_request, [ fake_http, nil ]) }

      assert_equal "AI HTTP 429", error.message
      assert_equal 4, fake_http.request_count
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

      assert_equal "AI HTTP 429 (Budget has been exceeded!)", error.message
      assert_equal 1, fake_http.request_count
    end

    test "chat_stream yields deltas in order and returns the full content" do
      sse_chunks = [
        "data: {\"choices\":[{\"delta\":{\"content\":\"COP \"}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\"23.400\"}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\".000\"}}]}\n\ndata: [DONE]\n\n"
      ]
      p = provider_with_streaming(sse_chunks)

      deltas = []
      response = p.chat_stream(messages: [ { role: "user", content: "hi" } ]) { |delta| deltas << delta }

      assert_equal [ "COP ", "23.400", ".000" ], deltas
      assert_equal "COP 23.400.000", response.content
    end

    test "chat_stream buffers partial SSE lines split across chunks" do
      sse_chunks = [
        "data: {\"choices\":[{\"delta\":{\"conten",
        "t\":\"Hola\"}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\" mundo\"}}]}\n\n"
      ]
      p = provider_with_streaming(sse_chunks)

      deltas = []
      response = p.chat_stream(messages: [ { role: "user", content: "hi" } ]) { |delta| deltas << delta }

      assert_equal [ "Hola", " mundo" ], deltas
      assert_equal "Hola mundo", response.content
    end

    test "streaming request body carries stream:true and no json mode" do
      _http, request = provider.send(
        :build_request, [ { role: "user", content: "hi" } ], 0.0, false, nil, 25, nil, stream: true
      )

      body = JSON.parse(request.body)
      assert_equal true, body["stream"]
      assert_not body.key?("response_format")
    end

    test "chat_stream ignores malformed SSE lines but keeps valid deltas" do
      sse = [ "data: not-json\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\n" ]
      p = provider_with_streaming(sse)

      deltas = []
      response = p.chat_stream(messages: [ { role: "user", content: "hi" } ]) { |delta| deltas << delta }

      assert_equal [ "ok" ], deltas
      assert_equal "ok", response.content
    end

    test "chat_stream raises when the provider is not configured" do
      unconfigured = Ai::Provider.new(name: "test", model: "m", api_key: nil, base_url: nil)

      assert_raises(Ai::Provider::Error) { unconfigured.chat_stream(messages: []) }
    end

    test "chat_stream raises on HTTP failure status" do
      p = provider
      fake_http = FakeStreamingHttp.new(code: "500", chunks: [ "boom" ], body: "boom")
      p.define_singleton_method(:build_request) do |*_args|
        [ fake_http, Net::HTTP::Post.new("/") ]
      end
      p.define_singleton_method(:sleep) { |_seconds| nil }

      assert_raises(Ai::Provider::Error) do
        p.chat_stream(messages: [ { role: "user", content: "hi" } ])
      end
    end

    private

    # Builds a provider whose streaming HTTP call is replaced by a fake that
    # emits `chunks` through response.read_body (the SSE body).
    def provider_with_streaming(chunks)
      p = provider
      fake_http = FakeStreamingHttp.new(code: "200", chunks: chunks)
      p.define_singleton_method(:build_request) do |*_args|
        request = Net::HTTP::Post.new("/")
        request.body = { stream: true, messages: [ { role: "user", content: "hi" } ] }.to_json
        [ fake_http, request ]
      end
      p.define_singleton_method(:sleep) { |_seconds| nil }
      p
    end
  end

  # Minimal Net::HTTP double for streaming tests: `start` yields,
  # `request` yields the response (block form), and read_body emits the
  # pre-loaded SSE chunks (or returns the full body for error statuses).
  class FakeStreamingHttp
    attr_reader :request_count

    def initialize(code:, chunks:, body: nil)
      @code = code
      @chunks = chunks
      @body = body
      @request_count = 0
    end

    def start
      yield
    end

    def request(_request)
      @request_count += 1
      response = FakeStreamingResponse.new(@code, @chunks, @body)
      yield response if block_given?
      response
    end
  end

  class FakeStreamingResponse
    attr_reader :code, :body

    def initialize(code, chunks, body)
      @code = code
      @chunks = chunks
      @body = body
    end

    def read_body(&block)
      return @body if !block_given? || @chunks.nil?

      @chunks.each { |chunk| block.call(chunk) }
      @body
    end
  end
end
