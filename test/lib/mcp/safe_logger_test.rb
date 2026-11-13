# frozen_string_literal: true

require "test_helper"

class McpSafeLoggerTest < ActiveSupport::TestCase
  test "drops info and debug but forwards warn and error" do
    io = StringIO.new
    logger = Mcp::SafeLogger.new(ActiveSupport::TaggedLogging.new(Logger.new(io)))

    logger.info("Sending result: secreto financiero")
    logger.debug("Received request")
    logger.warn("mcp warning")
    logger.error("mcp error")

    refute_includes io.string, "secreto financiero"
    refute_includes io.string, "Received request"
    assert_includes io.string, "mcp warning"
    assert_includes io.string, "mcp error"
  end

  test "reports info and debug as disabled" do
    logger = Mcp::SafeLogger.new(Logger.new(StringIO.new))

    refute logger.info?
    refute logger.debug?
  end
end
