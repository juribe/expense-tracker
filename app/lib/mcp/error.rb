# frozen_string_literal: true

module Mcp
  # Domain error with a stable machine-readable code. Tool errors never carry
  # stack traces or internal identifiers to the client.
  class Error < StandardError
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end
end
