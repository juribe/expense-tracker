# frozen_string_literal: true

require "delegate"

module Mcp
  # fast-mcp logs the full JSON-RPC tool result at INFO, which would copy account
  # balances and financial context into the shared log stream. This wrapper
  # drops INFO and DEBUG from that dependency while keeping warnings and errors.
  class SafeLogger < SimpleDelegator
    def add(severity, message = nil, progname = nil, &block)
      return true if severity.to_i < Logger::WARN

      __getobj__.add(severity, message, progname, &block)
    end

    def debug(*); true; end
    def info(*); true; end
    def debug?; false; end
    def info?; false; end
  end
end
