# frozen_string_literal: true

module Mcp
  # Authentication
  # Resolves the Bearer credential of an MCP request to its token record.
  # The token (never a request argument) decides which user data is visible.
  #
  # Example: Mcp::Authentication.call(authorization: "Bearer ygm_...")
  class Authentication
    class Unauthenticated < StandardError; end

    BEARER_PATTERN = /\ABearer\s+(\S+)\z/i

    def self.call(authorization:)
      new(authorization: authorization).call
    end

    def initialize(authorization:)
      @authorization = authorization.to_s
    end

    def call
      token = McpAccessToken.authenticate(plain_token)
      raise Unauthenticated if token.nil?

      token.touch_last_used!
      token
    end

    private

    def plain_token
      BEARER_PATTERN.match(@authorization)&.[](1)
    end
  end
end
