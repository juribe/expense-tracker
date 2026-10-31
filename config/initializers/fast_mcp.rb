# frozen_string_literal: true

# The gem ships lib/fast_mcp.rb, which Bundler does not auto-require from the
# hyphenated gem name. Loading it here also documents the integration point:
# tools are registered per request by Mcp::ServerFactory.
require "fast_mcp"
