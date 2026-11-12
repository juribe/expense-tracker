# frozen_string_literal: true

module Mcp
  # Mcp::EndpointController
  # Serves POST /mcp as a stateless JSON-RPC endpoint. The authenticated token
  # decides the user and the tool scopes; nothing is kept between requests.
  class EndpointController < ActionController::API
    before_action :authenticate_mcp!
    before_action :authorize_premium_access!, only: :create

    def create
      Mcp::Current.user = @mcp_token.user
      Mcp::Current.scopes = @mcp_token.scopes
      Mcp::Current.token = @mcp_token

      server = Mcp::ServerFactory.build(scopes: @mcp_token.scopes)
      response_payload = server.handle_request(request.raw_post, headers: request_headers)

      response_payload.nil? ? head(:accepted) : render(json: response_payload)
    end

    def method_not_allowed
      render json: {
        jsonrpc: "2.0",
        error: { code: -32_601, message: "Method not allowed" },
        id: nil
      }, status: :method_not_allowed
    end

    private

    def authenticate_mcp!
      @mcp_token = Mcp::Authentication.call(authorization: request.headers["Authorization"])
    rescue Mcp::Authentication::Unauthenticated
      render json: {
        jsonrpc: "2.0",
        error: { code: -32_001, message: "Unauthorized" },
        id: nil
      }, status: :unauthorized
    end

    # Membership is evaluated per authenticated user, so one expired account
    # never affects other MCP callers. Renewing restores access immediately:
    # tokens are not revoked and no state is cached between requests.
    def authorize_premium_access!
      return if PaymentEngine::AccessPolicy.premium_access?(@mcp_token.user)

      render json: {
        jsonrpc: "2.0",
        error: { code: -32_003, message: "Premium membership required" },
        id: nil
      }, status: :forbidden
    end

    def request_headers
      request.headers.to_h
             .select { |name, _value| name.start_with?("HTTP_") }
             .transform_keys { |name| name.delete_prefix("HTTP_").downcase.tr("_", "-") }
    end
  end
end
