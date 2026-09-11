# frozen_string_literal: true

module Ai
  module Tasks
    # A routable AI task. Each task knows which tiers may serve it, how to
    # build the model messages from the input, and how to parse the model's
    # JSON response into data plus a confidence score.
    #
    # The Router drives the lifecycle:
    #   1. cache_lookup(input, context) — return { data:, confidence: } to skip
    #      AI entirely, or nil to continue.
    #   2. messages(input, context) — chat messages sent to the provider.
    #   3. parse(content, context) — return { data:, confidence: } or raise
    #      InvalidResponse so the router escalates to the next tier.
    class Base
      class InvalidResponse < StandardError; end

      # Tiers tried in order. The cheap tier is only attempted when a cheap
      # provider is configured; the last tier accepts regardless of
      # confidence.
      def tiers
        %i[cheap strong]
      end

      def timeout
        25
      end

      def cache_lookup(input, context)
        nil
      end

      def messages(_input, _context)
        raise NotImplementedError
      end

      # Returns { data:, confidence: } where confidence is a 0..1 Float or
      # nil for tasks that do not produce a confidence score.
      def parse(_content, _input, _context)
        raise NotImplementedError
      end

      # Confidence threshold under which a cheap-tier result is escalated to
      # the strong tier.
      def confidence_threshold
        Ai.configuration.cheap_confidence_threshold
      end

      private

      def parse_json(content)
        payload = JSON.parse(content.to_s)
        raise InvalidResponse, "AI response is not a JSON object" unless payload.is_a?(Hash) || payload.is_a?(Array)

        payload
      rescue JSON::ParserError, TypeError => e
        raise InvalidResponse, "invalid AI response (#{e.message})"
      end
    end
  end
end
