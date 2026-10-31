# frozen_string_literal: true

module Mcp
  # Transport that captures one JSON-RPC response synchronously.
  #
  # fast-mcp's Rack transport replies over a process-local SSE stream, which
  # cannot work behind multiple Puma workers. The endpoint builds one server
  # per request and returns the captured response in the HTTP body.
  class HttpTransport < ::FastMcp::Transports::BaseTransport
    attr_reader :response

    def start
      self
    end

    def stop
      @response = nil
    end

    def send_message(message)
      @response = message
    end
  end
end
