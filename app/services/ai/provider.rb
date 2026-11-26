# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Ai
  # Base interface every AI provider implements. Business logic never talks to
  # a vendor endpoint directly; it receives a Provider and calls #chat.
  #
  #   response = provider.chat(messages: [ { role: "system", content: "..." } ])
  #   response.content       # => raw message content (String)
  #   response.input_tokens  # => Integer (0 when the API does not report usage)
  #
  # Raises Ai::Provider::Error on transport, HTTP and payload failures.
  class Provider
    Response = Struct.new(:content, :model, :input_tokens, :output_tokens, keyword_init: true)

    class Error < StandardError; end

    # Growing waits for transient 429 throttles without a provider hint: 2s, 5s, 10s.
    RETRY_BACKOFF_SECONDS = [ 2, 5, 10 ].freeze
    # Upstream 429s (OpenRouter "Provider returned error") carry a ~60s
    # Retry-After hint; retrying inside that window fails every time.
    MAX_RETRY_AFTER_SECONDS = 60
    # Bounds the total sleep per call so one resolution cannot stall a job.
    MAX_TOTAL_RETRY_WAIT_SECONDS = 90

    attr_reader :name, :model

    def initialize(name:, model:, api_key:, base_url:)
      @name = name
      @model = model
      @api_key = api_key
      @base_url = base_url
    end

    def configured?
      @api_key.present? && @base_url.present? && @model.present?
    end

    # messages follow the OpenAI chat-completions shape
    # ([ { role:, content: } ]); content may also be the multi-modal array form
    # used by vision models. Returns a Response. Raises Error on failure.
    def chat(messages:, temperature: 0.0, json: true, model: nil, timeout: 25, max_tokens: nil)
      raise Error, "AI provider #{name} is not configured" unless configured?

      response = perform_request(build_request(messages, temperature, json, model, timeout, max_tokens))

      payload = JSON.parse(response.body)
      content = payload.dig("choices", 0, "message", "content")
      raise Error, "AI response content is empty" if content.blank?

      Response.new(
        content: content,
        model: payload["model"].presence || model || @model,
        input_tokens: payload.dig("usage", "prompt_tokens").to_i,
        output_tokens: payload.dig("usage", "completion_tokens").to_i
      )
    rescue JSON::ParserError, TypeError, KeyError => e
      raise Error, "invalid AI response (#{e.message})"
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, EOFError => e
      raise Error, "AI request failed (#{e.message})"
    end

    # Streaming variant of #chat for conversational answers. Sends the same
    # request with stream:true and yields content deltas as they arrive over
    # the SSE wire; returns a Response with the full accumulated content.
    # Usage tokens are not reported by streaming endpoints, so they are 0.
    #
    #   provider.chat_stream(messages: messages) { |delta| ... }
    #
    # Raises Ai::Provider::Error on transport, HTTP and payload failures.
    def chat_stream(messages:, temperature: 0.0, model: nil, timeout: 30, max_tokens: nil)
      raise Error, "AI provider #{name} is not configured" unless configured?

      http, request = build_request(messages, temperature, false, model, timeout, max_tokens, stream: true)

      content = +""
      partial = +""
      handle_chunk = lambda do |chunk|
        partial << chunk
        # limit -1 keeps trailing empty strings: a complete "…\n\n" chunk
        # would otherwise lose its final data line (split drops it).
        lines = partial.split("\n", -1)
        partial.replace(lines.pop.to_s)
        lines.each do |line|
          delta = stream_delta(line)
          next if delta.blank?

          content << delta
          yield delta
        end
      end

      http.start do
        retry_with_backoff do
          http.request(request) do |response|
            next response.read_body unless response.code.to_i == 200

            response.read_body(&handle_chunk)
          end
        end
      end

      # A stream may end without a trailing newline; flush the leftover line.
      leftover = stream_delta(partial)
      if leftover.present?
        content << leftover
        yield leftover
      end

      Response.new(content: content, model: model || @model, input_tokens: 0, output_tokens: 0)
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, EOFError => e
      raise Error, "AI request failed (#{e.message})"
    end

    private

    # Vendor-specific headers (e.g. OpenRouter's attribution headers). Only
    # present when the client defines them.
    def extra_headers
      {}
    end

    def build_request(messages, temperature, json, model_override, timeout, max_tokens, stream: false)
      uri = URI(@base_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = timeout

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{@api_key}"
      extra_headers.each { |key, value| request[key] = value }
      body = {
        model: model_override || @model,
        temperature: temperature,
        messages: messages
      }
      body[:response_format] = { type: "json_object" } if json
      body[:stream] = true if stream
      body[:max_tokens] = max_tokens if max_tokens
      request.body = body.to_json

      [ http, request ]
    end

    # One SSE line ("data: {...}") → the delta text it carries, or nil for
    # keep-alives, [DONE] markers and malformed payloads.
    def stream_delta(line)
      payload = line.strip
      return nil unless payload.start_with?("data:")

      data = payload.delete_prefix("data:").strip
      return nil if data.empty? || data == "[DONE]"

      JSON.parse(data).dig("choices", 0, "delta", "content").to_s
    rescue JSON::ParserError
      nil
    end

    # Retries rate-limited (HTTP 429) responses with a short backoff; other
    # HTTP errors fail immediately. Accepts a callable so tests can stub HTTP.
    def perform_request((http, request))
      retry_with_backoff { http.request(request) }
    end

    # Retries transient rate limits (HTTP 429), honoring the provider's
    # Retry-After hint when present and falling back to a growing backoff
    # (2s, 5s, 10s): free-tier providers answer in per-minute bursts, so a
    # wait shorter than their hint still lands inside the throttled window.
    # A 429 reporting an exhausted budget or quota is not transient: fail fast
    # so the router can fall back to the strong tier immediately.
    def retry_with_backoff
      attempts = 0
      waited = 0
      loop do
        response = yield
        return response if response.code.to_i == 200

        wait = retry_wait(response, attempts, waited)
        raise_http_error(response) if wait.nil?

        attempts += 1
        waited += wait
        sleep(wait)
      end
    end

    # Seconds to wait before the next attempt, or nil when this response must
    # not be retried (non-429, retries exhausted, permanent throttle, or a
    # wait that would exceed the total budget).
    def retry_wait(response, attempts, waited)
      return nil unless response.code.to_i == 429
      return nil if attempts >= RETRY_BACKOFF_SECONDS.size
      return nil unless retryable_throttle?(response)

      wait = retry_after_seconds(response) || RETRY_BACKOFF_SECONDS[attempts]
      wait if waited + wait <= MAX_TOTAL_RETRY_WAIT_SECONDS
    end

    # Provider hint, capped so a single wait cannot stall the caller for long.
    def retry_after_seconds(response)
      seconds = header_retry_after(response) || body_retry_after(response)
      seconds&.clamp(1, MAX_RETRY_AFTER_SECONDS)
    end

    def header_retry_after(response)
      value = response["Retry-After"].to_s.strip
      value.to_i if value.match?(/\A\d+\z/)
    end

    # OpenRouter repeats the hint in the error body when the header is absent.
    def body_retry_after(response)
      metadata = JSON.parse(response.body.to_s).dig("error", "metadata")
      return nil unless metadata.is_a?(Hash)

      value = metadata["retry_after_seconds"] || metadata.dig("headers", "Retry-After")
      value.to_i if value.to_s.match?(/\A\d+\z/)
    rescue JSON::ParserError, TypeError
      nil
    end

    def raise_http_error(response)
      detail = api_error_message(response)
      raise Error, "AI HTTP #{response.code}#{detail ? " (#{detail})" : ""}"
    end

    # HTTP errors carry a vendor body ({ "message": ... } for Mistral, etc.);
    # without it a bare "AI HTTP 400" hides the real reason (bad model, bad
    # payload, ...).
    def api_error_message(response)
      parsed = JSON.parse(response.body)
      message = (parsed["message"] || parsed.dig("error", "message")).to_s.strip.presence
      return message if message

      response.body.to_s[0, 200].presence
    rescue JSON::ParserError, TypeError
      response.body.to_s[0, 200].presence
    end

    def retryable_throttle?(response)
      !response.body.to_s.match?(/budget|quota|insufficient/i)
    end
  end
end
