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
    def chat(messages:, temperature: 0.0, json: true, model: nil, timeout: 25)
      raise Error, "AI provider #{name} is not configured" unless configured?

      response = perform_request(build_request(messages, temperature, json, model, timeout))

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
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
      raise Error, "AI request failed (#{e.message})"
    end

    private

    # Vendor-specific headers (e.g. OpenRouter's attribution headers). Only
    # present when the client defines them.
    def extra_headers
      {}
    end

    def build_request(messages, temperature, json, model_override, timeout)
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
      request.body = body.to_json

      [ http, request ]
    end

    # Retries rate-limited (HTTP 429) responses with a short backoff; other
    # HTTP errors fail immediately. Accepts a callable so tests can stub HTTP.
    def perform_request((http, request))
      retry_with_backoff { http.request(request) }
    end

    # Retries transient rate limits (HTTP 429) with a short backoff. A 429
    # reporting an exhausted budget or quota is not transient: fail fast so
    # the router can fall back to the strong tier immediately.
    def retry_with_backoff
      attempts = 0
      loop do
        response = yield
        return response if response.code.to_i == 200

        if response.code.to_i == 429 && attempts < 2 && retryable_throttle?(response)
          attempts += 1
          sleep(attempts)
          next
        end

        raise Error, "AI HTTP #{response.code}"
      end
    end

    def retryable_throttle?(response)
      !response.body.to_s.match?(/budget|quota|insufficient/i)
    end
  end
end
