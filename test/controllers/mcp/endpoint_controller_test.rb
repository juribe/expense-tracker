# frozen_string_literal: true

require "test_helper"

class McpEndpointControllerTest < ActionController::TestCase
  tests Mcp::EndpointController

  test "does not forward the authorization header to tools" do
    request = ActionDispatch::TestRequest.create
    request.headers["Authorization"] = "Bearer ygm_secret"
    request.headers["X-Custom"] = "value"
    @controller.set_request!(request)

    headers = @controller.send(:request_headers)

    refute_includes headers.keys, "authorization"
    assert_equal "value", headers["x-custom"]
  end
end
